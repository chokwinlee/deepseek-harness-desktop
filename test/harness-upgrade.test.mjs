import assert from 'node:assert/strict'
import test from 'node:test'
import { mkdtemp, mkdir, writeFile, readFile, readdir, rm, stat, symlink } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import { spawn, spawnSync } from 'node:child_process'
import { zstdCompressSync } from 'node:zlib'
import { once } from 'node:events'
import { WebSocket } from 'ws'
import { backupHome, migrateSessions, HARNESS_VERSION } from '../src/dsh-desktop-settings-plugin/lib/upgrade.js'
import { connectLoopback, callRemote } from '../src/dsh-desktop-settings-plugin/lib/rpc.js'
import { createLanRemoteServer } from '../scripts/lan-remote-proxy.mjs'
import { promptReceipts } from '../src/dsh-desktop-settings-plugin/lib/remote-v1.js'

test('Remote retries share admission before the upstream journal catches up and failed admissions can retry', async () => {
  const admit = promptReceipts(2)
  let release
  let calls = 0
  const first = admit('session', 'request', () => {
    calls++
    return new Promise(resolve => { release = resolve })
  })
  const concurrent = admit('session', 'request', () => { throw new Error('duplicate admission') })
  await Promise.resolve()
  release({ accepted: true })
  assert.deepEqual(await Promise.all([first, concurrent]), [{ accepted: true }, { accepted: true }])
  assert.deepEqual(await admit('session', 'request', () => { throw new Error('journal publication gap') }), { accepted: true })
  assert.equal(calls, 1)
  await assert.rejects(admit('session', 'failed', () => { throw new Error('model unavailable') }), /model unavailable/)
  assert.deepEqual(await admit('session', 'failed', () => ({ accepted: true })), { accepted: true })
  let otherSession = false
  await admit('other-session', 'request', () => { otherSession = true; return { accepted: true } })
  assert.equal(otherSession, true, 'request identities are scoped to a session')
})

test('production pruning never deletes source behind a local package symlink', async t => {
  const root = await mkdtemp(join(tmpdir(), 'dsh-prune-test-'))
  t.after(() => rm(root, { recursive: true, force: true }))
  await mkdir(join(root, 'modules')); await mkdir(join(root, 'source'))
  await writeFile(join(root, 'source/rpc.d.ts'), 'source declaration')
  await symlink(join(root, 'source'), join(root, 'modules/local-plugin'), process.platform === 'win32' ? 'junction' : 'dir')
  const result = spawnSync(process.execPath, ['scripts/prune-runtime.mjs', join(root, 'modules')])
  assert.equal(result.status, 0)
  assert.equal(await readFile(join(root, 'source/rpc.d.ts'), 'utf8'), 'source declaration')
})

test('migration preserves source bytes, reports refusal, and verifies its immutable backup on restart', async t => {
  const home = await mkdtemp(join(tmpdir(), 'dsh-upgrade-test-'))
  t.after(() => rm(home, { recursive: true, force: true }))
  for (const id of ['valid', 'unsupported']) {
    const directory = join(home, 'sessions', '_no-cwd', id)
    await mkdir(directory, { recursive: true })
    const rows = [{ type: 'session', version: 0, id, createdAt: 1, delegationDepth: 0 }, { type: id === 'valid' ? 'permission/preset' : 'unknown/required-event', seq: 0, time: 2, data: { preset: 'workspace-write' } }]
    await writeFile(join(directory, 'session.jsonl.zstd'), Buffer.concat(rows.map(row => zstdCompressSync(JSON.stringify(row) + '\n'))))
  }
  await writeFile(join(home, 'settings.json'), '{"private":"fixture"}')
  const backup = await backupHome(home)
  if (process.platform !== 'win32') {
    assert.equal((await stat(join(backup, 'data/settings.json'))).mode & 0o777, 0o600)
  }
  const report = await migrateSessions(home, backup)
  assert.deepEqual(report.migrated, ['valid'])
  assert.deepEqual(report.refused.map(item => item.id), ['unsupported'])
  for (const id of ['valid', 'unsupported']) {
    const path = `sessions/_no-cwd/${id}/session.jsonl.zstd`
    assert.deepEqual(await readFile(join(home, path)), await readFile(join(backup, 'data', path)))
  }
  assert.ok((await readdir(join(home, 'sessions/_no-cwd/valid'))).some(name => name.startsWith('session.v3.jsonl')))
  assert.ok(!(await readdir(join(home, 'sessions/_no-cwd/unsupported'))).some(name => name.startsWith('session.v3.jsonl')))
  assert.deepEqual(await migrateSessions(home, backup), report)
  await writeFile(join(home, 'settings.json'), '{"private":"new work"}')
  assert.equal(await backupHome(home), backup)
  await writeFile(join(backup, 'data/settings.json'), 'damaged')
  await assert.rejects(backupHome(home), /backup is damaged/)
})

test('packaged plugin keeps modern RPC, Remote v1, authenticated proxy and live streams interoperable', { timeout: 60000 }, async t => {
  const home = await mkdtemp(join(tmpdir(), 'dsh-transport-test-'))
  await mkdir(join(home, 'profiles/web/node_modules'), { recursive: true })
  await symlink(resolve('src/dsh-desktop-settings-plugin'), join(home, 'profiles/web/node_modules/dsh-desktop-settings-plugin'), process.platform === 'win32' ? 'junction' : 'dir')
  const child = spawn(process.execPath, ['--expose-internals', 'src/dsh-desktop-settings-plugin/lib/launch.js', '--profile', 'web', '--patch', resolve('src/dsh-desktop-settings-plugin/desktop.patch.yml'), '--host', '127.0.0.1', '--port', '0', '--no-open'], { cwd: resolve('.'), env: { ...process.env, DSH_HOME: home }, stdio: ['ignore', 'pipe', 'pipe'] })
  t.after(async () => { if (child.exitCode === null) { child.kill('SIGTERM'); await once(child, 'exit') }; await rm(home, { recursive: true, force: true }) })
  const url = await new Promise((resolveUrl, reject) => {
    let output = ''
    const timeout = setTimeout(() => reject(new Error('Harness readiness timed out')), 30000)
    const capture = data => { output = (output + data).slice(-8192); const match = output.match(/dsh web: (\S+)/); if (match) { clearTimeout(timeout); resolveUrl(match[1]) } }
    child.stdout.on('data', capture); child.stderr.on('data', capture)
    child.once('exit', code => { clearTimeout(timeout); reject(new Error(`Harness exited before readiness: ${code} ${output.replace(/token=[^\s]+/g, 'token=[redacted]')}`)) })
  })
  const connection = await connectLoopback(url)
  assert.equal((await fetch(connection.origin)).status, 401)
  assert.ok((await callRemote(connection, 'settings/describe', {})).namespaces.length)
  const target = new URL(connection.origin); target.dshCookie = connection.cookie
  const proxy = createLanRemoteServer(target, 'remote-test-token')
  proxy.listen(0, '127.0.0.1'); await once(proxy, 'listening')
  t.after(() => { proxy.closeAllConnections(); proxy.close() })
  const origin = `http://127.0.0.1:${proxy.address().port}`
  const call = async (method, payload = {}, authenticated = true) => {
    const response = await fetch(`${origin}/api/${method}`, { method: 'POST', headers: { 'content-type': 'application/json', ...(authenticated ? { authorization: 'Bearer remote-test-token' } : {}) }, body: JSON.stringify({ type: 'client-request', rpcId: 'compatibility-test', method, payload }) })
    return { response, body: response.ok ? await response.json() : await response.text() }
  }
  assert.equal((await call('host.describe', {}, false)).response.status, 401)
  assert.equal((await call('host.describe')).body.result.value.version, HARNESS_VERSION)
  assert.equal((await call('settings/describe', { args: {} })).response.status, 404)
  const created = (await call('session.create', { cwd: home })).body.result.value
  assert.ok(created.sessionId)
  const history = (await call('session.history', { sessionId: created.sessionId })).body.result
  assert.equal(history.ok, true); assert.ok(history.value.events.length)
  assert.ok((await call('session.models', { sessionId: created.sessionId })).body.result.value.current.model)
  const socket = new WebSocket(`${origin.replace('http:', 'ws:')}/api/events.mux`, { headers: { authorization: 'Bearer remote-test-token' } })
  t.after(() => socket.terminate())
  const [frame] = await once(socket, 'message')
  assert.match(JSON.parse(String(frame)).payload.type, /^session\//)
  socket.close(); await once(socket, 'close')
  assert.equal((await call('session.cancel', { sessionId: created.sessionId })).body.result.value.accepted, true)
  assert.ok((await callRemote(connection, 'settings/describe', {})).namespaces.length, 'legacy routes must not replace the modern gateway interceptor')
})
