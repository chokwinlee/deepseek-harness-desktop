import { createRequire } from 'node:module'
import { dirname, join } from 'node:path'
import { app, BrowserWindow, dialog, Menu, shell, type MenuItemConstructorOptions } from 'electron'
import { HarnessSupervisor } from './harness-supervisor.js'
import { suppressUpstreamWelcomeNotice } from './upstream-onboarding.js'

const APP_NAME = 'DeepSeek Harness Desktop'
const LOADING_PAGE = `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${APP_NAME}</title>
  <style>
    :root { color-scheme: light dark; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
    body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: #f7f8fa; color: #111827; }
    main { display: grid; justify-items: center; gap: 18px; }
    .mark { width: 72px; height: 72px; display: grid; place-items: center; border-radius: 22px; background: linear-gradient(145deg, #4f8cff, #2458d3); color: white; font-weight: 750; letter-spacing: -1px; box-shadow: 0 18px 45px #2458d333; }
    .spinner { width: 22px; height: 22px; border: 2px solid #8da3c933; border-top-color: #3975eb; border-radius: 50%; animation: spin 850ms linear infinite; }
    p { margin: 0; color: #667085; font-size: 14px; }
    @keyframes spin { to { transform: rotate(360deg); } }
    @media (prefers-color-scheme: dark) { body { background: #111318; color: #f3f4f6; } p { color: #98a2b3; } }
  </style>
</head>
<body><main><div class="mark">DSH</div><div class="spinner"></div><p>Starting DeepSeek Harness…</p></main></body>
</html>`

app.setName(APP_NAME)

const hasSingleInstanceLock = app.requestSingleInstanceLock()
if (!hasSingleInstanceLock) app.quit()

let mainWindow: BrowserWindow | undefined
let harnessUrl: string | undefined
let supervisor: HarnessSupervisor | undefined
let shutdownStarted = false

function resolveDshBin(): string {
  if (app.isPackaged) {
    return join(
      process.resourcesPath,
      'app.asar.unpacked',
      'node_modules',
      '@deepseek-ai',
      'dsh',
      'lib',
      'bin.js',
    )
  }
  const require = createRequire(import.meta.url)
  const manifest = require.resolve('@deepseek-ai/dsh/package.json')
  return join(dirname(manifest), 'lib', 'bin.js')
}

function isExternalUrl(rawUrl: string): boolean {
  try {
    const protocol = new URL(rawUrl).protocol
    return protocol === 'https:' || protocol === 'http:' || protocol === 'mailto:'
  } catch {
    return false
  }
}

function isHarnessPage(rawUrl: string): boolean {
  if (harnessUrl === undefined) return false
  try {
    return new URL(rawUrl).origin === new URL(harnessUrl).origin
  } catch {
    return false
  }
}

function isLoadingPage(rawUrl: string): boolean {
  return harnessUrl === undefined && rawUrl.startsWith('data:text/html;charset=utf-8,')
}

async function openExternal(rawUrl: string): Promise<void> {
  if (isExternalUrl(rawUrl)) await shell.openExternal(rawUrl)
}

function createWindow(): BrowserWindow {
  const window = new BrowserWindow({
    title: APP_NAME,
    width: 1440,
    height: 900,
    minWidth: 960,
    minHeight: 640,
    show: false,
    backgroundColor: '#f7f8fa',
    icon: join(app.getAppPath(), 'build', 'icon.png'),
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  })

  window.webContents.setWindowOpenHandler(({ url }) => {
    void openExternal(url)
    return { action: 'deny' }
  })
  window.webContents.on('will-navigate', (event, url) => {
    if (isHarnessPage(url) || isLoadingPage(url)) return
    event.preventDefault()
    void openExternal(url)
  })
  window.webContents.session.setPermissionRequestHandler((_contents, _permission, callback) => {
    callback(false)
  })
  window.once('ready-to-show', () => { window.show() })
  window.on('closed', () => {
    if (mainWindow === window) mainWindow = undefined
  })
  return window
}

function installMenu(): void {
  const template: MenuItemConstructorOptions[] = [
    ...(process.platform === 'darwin'
      ? [{ role: 'appMenu' as const }]
      : [{ role: 'fileMenu' as const }]),
    { role: 'editMenu' },
    { role: 'viewMenu' },
    { role: 'windowMenu' },
  ]
  Menu.setApplicationMenu(Menu.buildFromTemplate(template))
}

async function showHarness(): Promise<void> {
  mainWindow ??= createWindow()
  if (harnessUrl === undefined) {
    await mainWindow.loadURL(`data:text/html;charset=utf-8,${encodeURIComponent(LOADING_PAGE)}`)
    return
  }
  await mainWindow.loadURL(harnessUrl)
  mainWindow.show()
  mainWindow.focus()
}

async function boot(): Promise<void> {
  installMenu()
  await showHarness()
  supervisor = new HarnessSupervisor({
    executable: process.execPath,
    script: resolveDshBin(),
    cwd: app.getPath('home'),
    env: {
      ...process.env,
      ELECTRON_RUN_AS_NODE: '1',
    },
    onLog: (source, line) => {
      const output = source === 'stderr' ? console.error : console.log
      output(`[dsh:${source}] ${line}`)
    },
  })
  const startedUrl = await supervisor.start()
  await suppressUpstreamWelcomeNotice(startedUrl)
  harnessUrl = startedUrl
  await showHarness()
}

async function shutdown(exitCode = 0): Promise<void> {
  if (shutdownStarted) return
  shutdownStarted = true
  try {
    await supervisor?.stop()
  } finally {
    app.exit(exitCode)
  }
}

if (hasSingleInstanceLock) {
  app.on('second-instance', () => {
    if (mainWindow?.isMinimized() === true) mainWindow.restore()
    mainWindow?.show()
    mainWindow?.focus()
  })
  app.on('activate', () => {
    if (app.isReady()) void showHarness()
  })
  app.on('window-all-closed', () => {
    if (process.platform !== 'darwin') app.quit()
  })
  app.on('before-quit', (event) => {
    if (shutdownStarted) return
    event.preventDefault()
    void shutdown()
  })

  void app.whenReady().then(boot).catch(async (error: unknown) => {
    const message = error instanceof Error ? error.message : String(error)
    dialog.showErrorBox('DeepSeek Harness failed to start', message)
    await shutdown(1)
  })
}
