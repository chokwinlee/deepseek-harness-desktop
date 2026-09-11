import { createHash, randomUUID } from 'node:crypto'
import { constants } from 'node:fs'
import { copyFile, lstat, mkdir, readFile, readdir, readlink, rename, rm, writeFile, chmod } from 'node:fs/promises'
import { join, relative } from 'node:path'

export const HARNESS_VERSION = '0.1.5-rc.2'
const excluded = new Set(['node_modules', '.cache', 'desktop-upgrades'])
const hash = bytes => createHash('sha256').update(bytes).digest('hex')

// Capture links as links in the inventory, never follow them into unrelated data.
async function inventory(root, directory = root) {
  const entries = []
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    if (excluded.has(entry.name)) continue
    const path = join(directory, entry.name)
    const name = relative(root, path)
    if (entry.isSymbolicLink()) entries.push({ path: name, link: await readlink(path) })
    else if (entry.isDirectory()) entries.push(...await inventory(root, path))
    else if (entry.isFile()) entries.push({ path: name, sha256: hash(await readFile(path)) })
  }
  return entries.sort((a, b) => a.path.localeCompare(b.path))
}

/** Snapshot once, verify every byte and publish atomically before upgrading. */
export async function backupHome(home, version = HARNESS_VERSION) {
  if (!/^\d+\.\d+\.\d+(?:-[a-z0-9.]+)?$/.test(version)) throw new Error('Invalid backup version')
  await mkdir(home, { recursive: true, mode: 0o700 })
  const parent = join(home, 'desktop-upgrades')
  await mkdir(parent, { recursive: true, mode: 0o700 })
  const destination = join(parent, version)
  try {
    const receipt = JSON.parse(await readFile(join(destination, 'backup.json'), 'utf8'))
    if (receipt.version !== version || receipt.home !== home) throw new Error('Mismatched upgrade backup')
    for (const item of receipt.files) {
      if (item.sha256 && hash(await readFile(join(destination, 'data', item.path))) !== item.sha256) throw new Error(`Upgrade backup is damaged: ${item.path}`)
    }
    return destination
  } catch (error) { if (error.code !== 'ENOENT') throw error }
  const stage = join(parent, `.${version}-${randomUUID()}`)
  await mkdir(join(stage, 'data'), { recursive: true, mode: 0o700 })
  try {
    const before = await inventory(home)
    for (const item of before) {
      if (item.link !== undefined) continue // recorded for deliberate recovery, not activated in backup
      const destinationFile = join(stage, 'data', item.path)
      await mkdir(join(destinationFile, '..'), { recursive: true, mode: 0o700 })
      await copyFile(join(home, item.path), destinationFile, constants.COPYFILE_EXCL)
      await chmod(destinationFile, 0o600)
      if (hash(await readFile(destinationFile)) !== item.sha256) throw new Error(`Data changed during backup: ${item.path}`)
    }
    if (JSON.stringify(before) !== JSON.stringify(await inventory(home))) throw new Error('DSH data changed during backup; quit other DSH processes and retry')
    await writeFile(join(stage, 'backup.json'), JSON.stringify({ version, home, createdAt: new Date().toISOString(), files: before }, null, 2), { mode: 0o600, flag: 'wx' })
    await rename(stage, destination)
    return destination
  } finally { await rm(stage, { recursive: true, force: true }) }
}

/** Official migrator creates verified V3 successors, leaving V0 bytes intact. */
export async function migrateSessions(home, backup) {
  const reportPath = join(backup, 'migration.json')
  try { return JSON.parse(await readFile(reportPath, 'utf8')) } catch (error) { if (error.code !== 'ENOENT') throw error }
  const root = join(home, 'sessions')
  const report = { version: HARNESS_VERSION, completedAt: '', migrated: [], refused: [] }
  try {
    if (!(await lstat(root)).isDirectory()) throw new Error('Session storage must be a local directory; migration stopped')
  } catch (error) { if (error.code !== 'ENOENT') throw error; return report }
  const { Context } = await import('@deepseek-ai/cordis')
  const { default: Persistence } = await import('@deepseek-ai/dsh-session-persistence-jsonl')
  const ctx = new Context()
  try {
    await ctx.plugin(Persistence, { root, compression: 'zstd' })
    for (const snapshot of await ctx.sessionPersistence.list()) {
      const id = snapshot.header.id
      let handle
      try {
        handle = await ctx.sessionPersistence.open(id, 'write')
        await handle.read()
        report.migrated.push(id)
      } catch (error) {
        report.refused.push({ id, reason: error.message })
      } finally { await handle?.close() }
    }
  } finally { await ctx.fiber.dispose() }
  report.completedAt = new Date().toISOString()
  const temp = `${reportPath}.${randomUUID()}.tmp`
  await writeFile(temp, JSON.stringify(report, null, 2), { mode: 0o600, flag: 'wx' })
  await rename(temp, reportPath)
  return report
}
