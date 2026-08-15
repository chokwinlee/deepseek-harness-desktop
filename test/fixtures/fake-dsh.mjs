import { createServer } from 'node:http'
import { readFile, writeFile } from 'node:fs/promises'
import { join } from 'node:path'

const mode = process.env.FAKE_DSH_MODE ?? 'ready'
const args = process.argv.slice(2)

const stop = () => { process.exit(0) }
process.on('SIGTERM', stop)
process.on('SIGINT', stop)

const profileManifest = () => join(process.env.DSH_HOME ?? '', 'profiles', 'web', 'package.json')

if (args[0] === 'plugin') {
  if (mode === 'plugin-install-ready') {
    const path = profileManifest()
    const manifest = JSON.parse(await readFile(path, 'utf8'))
    const name = process.env.FAKE_PLUGIN_NAME ?? 'fixture-plugin'
    const spec = args.at(-1) ?? name
    manifest.dependencies = { ...(manifest.dependencies ?? {}), [name]: spec }
    manifest.dsh ??= {}
    manifest.dsh.profile ??= {}
    manifest.dsh.profile.bundles ??= []
    if (!manifest.dsh.profile.bundles.includes(name)) manifest.dsh.profile.bundles.push(name)
    await writeFile(path, `${JSON.stringify(manifest, null, 2)}\n`)
    console.log(`fixture installed ${name}`)
    process.exit(0)
  }
  console.error('fixture plugin install failed')
  process.exit(13)
}

function serveFixture(body = 'Harness fixture ready') {
  const desktopAction = process.env.FAKE_DESKTOP_ACTION_URL
  const actionScript = desktopAction
    ? `<script>setTimeout(() => location.assign(${JSON.stringify(desktopAction)}), 500)</script>`
    : ''
  const server = createServer((_request, response) => {
    response.writeHead(200, { 'content-type': 'text/html; charset=utf-8' })
    response.end(`<!doctype html><title>Harness fixture</title><main>${body}</main><button aria-haspopup="dialog" aria-expanded="false">设置</button>${actionScript}`)
  })
  server.listen(0, '127.0.0.1', () => {
    const address = server.address()
    if (!address || typeof address === 'string') process.exit(11)
    console.log(`dsh web: http://127.0.0.1:${String(address.port)}`)
  })
}

if (mode === 'ready') {
  console.log('booting')
  console.log('dsh web: http://127.0.0.1:43123')
} else if (mode === 'exit') {
  console.error('fixture startup failed')
  setTimeout(() => { process.exit(7) }, 10)
} else if (mode === 'unstable') {
  console.log('dsh web: http://127.0.0.1:43123')
  console.error('fixture crashed after readiness')
  setTimeout(() => { process.exit(9) }, 10)
} else if (mode === 'runtime-exit') {
  console.log('dsh web: http://127.0.0.1:43123')
  console.error('fixture exits after the readiness grace')
  setTimeout(() => { process.exit(10) }, 1_000)
} else if (mode === 'normal-fails-safe-ready') {
  if (process.argv.includes('desktop-safe')) {
    serveFixture('Harness safe mode ready')
  } else {
    console.error('failed to apply loader entry daily-review (dsh-daily-review)')
    setTimeout(() => { process.exit(12) }, 10)
  }
} else if (mode === 'plugin-install-ready') {
  const manifest = JSON.parse(await readFile(profileManifest(), 'utf8'))
  const name = process.env.FAKE_PLUGIN_NAME ?? 'fixture-plugin'
  if (process.env.FAKE_PLUGIN_RESTART_FAILURE === '1' && manifest.dependencies?.[name]) {
    console.error(`failed to apply loader entry fixture (${name})`)
    setTimeout(() => { process.exit(14) }, 10)
  } else {
    serveFixture(manifest.dependencies?.[name] ? 'Harness fixture with plugin' : 'Harness fixture before plugin')
  }
} else if (mode !== 'silent') {
  console.error(`unknown fixture mode: ${mode}`)
  process.exit(8)
}

setInterval(() => {}, 1_000)
