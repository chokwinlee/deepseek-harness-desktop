import { homedir } from 'node:os'
import { dirname, join } from 'node:path'
import { createRequire } from 'node:module'
import { pathToFileURL } from 'node:url'
import { backupHome, migrateSessions } from './upgrade.js'
const require = createRequire(import.meta.url)
if (!process.argv.slice(2).some(value => ['--version', '-V', '--help', '-h'].includes(value))) {
  const home = process.env.DSH_HOME || join(homedir(), '.dsh')
  const backup = await backupHome(home)
  const report = await migrateSessions(home, backup)
  if (report.refused.length) console.error(`[dsh-desktop] ${report.refused.length} historical sessions could not be migrated. Originals retained; report: ${join(backup, 'migration.json')}`)
}
const bin = join(dirname(require.resolve('@deepseek-ai/dsh/package.json')), 'lib/bin.js')
process.argv[1] = bin
const { runCli } = await import(pathToFileURL(bin).href)
await runCli()
