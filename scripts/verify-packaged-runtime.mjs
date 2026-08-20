import { spawn } from 'node:child_process'
import { access, mkdtemp, readdir, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { basename, dirname, join, resolve } from 'node:path'
import { pathToFileURL } from 'node:url'

const PRODUCT_NAME = 'DSH Desktop'
const READY_LINE = /dsh web:\s+(http:\/\/127\.0\.0\.1:\d+)/
const STARTUP_TIMEOUT_MS = 60_000
const STABILITY_WINDOW_MS = 3_000

async function findUnpackedDirectories(root) {
  const found = []
  const pending = [root]

  while (pending.length > 0) {
    const current = pending.pop()
    if (current === undefined) break
    let entries
    try {
      entries = await readdir(current, { withFileTypes: true })
    } catch (error) {
      if (error?.code === 'ENOENT') continue
      throw error
    }

    for (const entry of entries) {
      if (!entry.isDirectory()) continue
      const path = join(current, entry.name)
      if (entry.name === 'app.asar.unpacked') found.push(path)
      else pending.push(path)
    }
  }

  return found
}

function resolveRuntimeExecutable(unpackedDirectory) {
  const resourcesDirectory = dirname(unpackedDirectory)
  const contentsDirectory = dirname(resourcesDirectory)
  const appDirectory = dirname(contentsDirectory)

  if (basename(appDirectory).endsWith('.app')) {
    return join(contentsDirectory, 'MacOS', PRODUCT_NAME)
  }

  return join(contentsDirectory, `${PRODUCT_NAME}.exe`)
}

async function stopProcess(child) {
  if (child.exitCode !== null || child.signalCode !== null) return
  const exited = new Promise(resolveExit => child.once('exit', resolveExit))
  child.kill('SIGTERM')
  const stopped = await Promise.race([
    exited.then(() => true),
    new Promise(resolveTimeout => setTimeout(() => resolveTimeout(false), 5_000)),
  ])
  if (!stopped && child.exitCode === null && child.signalCode === null) {
    child.kill('SIGKILL')
    await exited
  }
}

async function packageNames(scopeDirectory) {
  const entries = await readdir(scopeDirectory, { withFileTypes: true })
  const names = []
  for (const entry of entries) {
    if (!entry.isDirectory()) continue
    try {
      await access(join(scopeDirectory, entry.name, 'package.json'))
      names.push(entry.name)
    } catch (error) {
      if (error?.code !== 'ENOENT') throw error
    }
  }
  return names.sort()
}

async function verifyDeepSeekDependencyClosure(modulesDirectory) {
  const sourceScope = resolve('node_modules', '@deepseek-ai')
  const packagedScope = join(modulesDirectory, '@deepseek-ai')
  const [sourcePackages, packagedPackages] = await Promise.all([
    packageNames(sourceScope),
    packageNames(packagedScope),
  ])
  const packagedSet = new Set(packagedPackages)
  const missing = sourcePackages.filter(name => !packagedSet.has(name))
  if (missing.length > 0) {
    throw new Error(`Packaged Harness is missing @deepseek-ai runtime packages:\n${missing.join('\n')}`)
  }
}

async function waitForHttpReady(url, child, readOutput) {
  const deadline = Date.now() + STARTUP_TIMEOUT_MS
  let lastError

  while (Date.now() < deadline) {
    if (child.exitCode !== null || child.signalCode !== null) {
      throw new Error(`Packaged Harness exited before HTTP readiness.\n${readOutput()}`)
    }
    try {
      const response = await fetch(url, { signal: AbortSignal.timeout(5_000) })
      if (response.ok) {
        await response.arrayBuffer()
        return
      }
      lastError = new Error(`HTTP ${String(response.status)}`)
    } catch (error) {
      lastError = error
    }
    await new Promise(resolveDelay => setTimeout(resolveDelay, 200))
  }

  throw new Error(`Packaged Harness did not answer at ${url}: ${String(lastError)}\n${readOutput()}`)
}

async function verifyStableProcess(child, readOutput) {
  await new Promise((resolveStable, rejectStable) => {
    const timeout = setTimeout(resolveStable, STABILITY_WINDOW_MS)
    child.once('exit', (code, signal) => {
      clearTimeout(timeout)
      rejectStable(new Error(`Packaged Harness exited after HTTP readiness (code ${String(code)}, signal ${String(signal)}).\n${readOutput()}`))
    })
  })
}

async function smokeRuntime(runtimeExecutable, dshBin) {
  const dshHome = await mkdtemp(join(tmpdir(), 'dsh-desktop-smoke-'))
  const child = spawn(
    runtimeExecutable,
    ['--expose-internals', dshBin, 'web', '--host', '127.0.0.1', '--port', '0', '--no-open'],
    {
      env: {
        ...process.env,
        DSH_HOME: dshHome,
        ELECTRON_RUN_AS_NODE: '1',
      },
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true,
    },
  )
  let output = ''
  const readOutput = () => output

  try {
    const readyUrl = await new Promise((resolveReady, rejectReady) => {
      let settled = false
      const finish = (action, value) => {
        if (settled) return
        settled = true
        clearTimeout(timeout)
        action(value)
      }
      const accept = chunk => {
        output = `${output}${chunk.toString()}`.slice(-12_000)
        const match = READY_LINE.exec(output)
        if (match !== null) finish(resolveReady, match[1])
      }
      const timeout = setTimeout(() => {
        finish(rejectReady, new Error(`Packaged Harness did not become ready.\n${output}`))
      }, STARTUP_TIMEOUT_MS)

      child.stdout.on('data', accept)
      child.stderr.on('data', accept)
      child.once('error', error => finish(rejectReady, error))
      child.once('exit', (code, signal) => {
        finish(rejectReady, new Error(`Packaged Harness exited early (code ${String(code)}, signal ${String(signal)}).\n${output}`))
      })
    })
    await waitForHttpReady(readyUrl, child, readOutput)
    await verifyStableProcess(child, readOutput)
  } finally {
    await stopProcess(child)
    await rm(dshHome, { recursive: true, force: true })
  }
}

const releaseDirectory = resolve(process.argv[2] ?? 'release')
const unpackedDirectories = await findUnpackedDirectories(releaseDirectory)
if (unpackedDirectories.length === 0) {
  throw new Error(`No app.asar.unpacked directory found under ${releaseDirectory}`)
}

for (const unpackedDirectory of unpackedDirectories) {
  const modulesDirectory = join(unpackedDirectory, 'node_modules')
  const bootEntry = join(modulesDirectory, '@deepseek-ai', 'dsh-app-boot', 'lib', 'index.js')
  const dshBin = join(modulesDirectory, '@deepseek-ai', 'dsh', 'lib', 'bin.js')
  const runtimeExecutable = resolveRuntimeExecutable(unpackedDirectory)

  await Promise.all([access(bootEntry), access(dshBin), access(runtimeExecutable)])
  await verifyDeepSeekDependencyClosure(modulesDirectory)
  await import(`${pathToFileURL(bootEntry).href}?packaged-runtime-check`)
  await smokeRuntime(runtimeExecutable, dshBin)
  console.log(`Packaged Harness runtime ready: ${runtimeExecutable}`)
}
