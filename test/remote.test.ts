import assert from 'node:assert/strict'
import { readFile, readdir } from 'node:fs/promises'
import http, { type Server } from 'node:http'
import { type AddressInfo } from 'node:net'
import { join } from 'node:path'
import { pathToFileURL } from 'node:url'
import { PassThrough, Writable } from 'node:stream'
import test from 'node:test'
import { runInNewContext } from 'node:vm'

interface RemoteTestApi {
  actionUrl: (
    action: string,
    token?: string,
    parameters?: Record<string, string | number | boolean>,
  ) => string
  authoritativeOperationOutcome: (
    operation: Record<string, unknown> | undefined,
    status: Record<string, unknown> | undefined,
  ) => string
  copyFor: (language: 'zh' | 'en') => Record<string, string>
  languageFromTag: (tag: string) => 'zh' | 'en'
  normalizeOperation: (value?: Record<string, unknown>) => Record<string, unknown>
  normalizeStatus: (value?: Record<string, unknown>) => Record<string, unknown>
  normalizedOperationStage: (value?: string) => string
  operationProgress: (value?: Record<string, unknown>) => Record<string, unknown>
  pendingActionAfterStatus: (
    pendingAction: string,
    value: Record<string, unknown> | undefined,
    transport: 'lan' | 'tailscale',
  ) => string
  shouldPollStatus: (
    value: Record<string, unknown> | undefined,
    surfaceVisible: boolean,
    pageVisible?: boolean,
    requestInFlight?: boolean,
  ) => boolean
  shouldDeferTerminalPresentation: (
    resumeId: string,
    value?: Record<string, unknown>,
  ) => boolean
  shouldRestoreOperation: (
    resumeId: string,
    value?: Record<string, unknown>,
  ) => boolean
  shouldAutoOpenLanPairing: (
    requested: boolean,
    previous: Record<string, unknown> | undefined,
    next: Record<string, unknown> | undefined,
  ) => boolean
  statusAfterError: (
    value: Record<string, unknown> | undefined,
    transport: 'lan' | 'tailscale',
    message: string,
  ) => Record<string, unknown>
  tailscaleGuideState: (
    value: Record<string, unknown> | undefined,
    language?: 'zh' | 'en',
  ) => Record<string, unknown>
  transportViewState: (
    value: Record<string, unknown> | undefined,
    transport: 'lan' | 'tailscale',
    language?: 'zh' | 'en',
    pendingAction?: string,
    otherPendingAction?: string,
  ) => Record<string, unknown>
}

interface LanRemoteProxyTestApi {
  MAX_BODY_BYTES: number
  createLanRemoteServer: (target: URL, token: string) => Server
  forwardRequestBody: (request: PassThrough, upstream: Writable, maxBytes?: number) => Promise<number>
  inspectDeclaredBodyLength: (
    value: string | string[] | undefined,
    maxBytes?: number,
  ) => { status: 'ok' | 'invalid' | 'too-large'; bytes?: number }
  proxyHeaders: (
    request: { headers: Record<string, string | undefined> },
    target: URL,
    declaredBytes?: number,
  ) => Record<string, string>
  streamedBodyExceedsLimit: (bytes: number, maxBytes?: number) => boolean
}

const EXPECTED_LAN_REMOTE_HTTP_PATHS = [
  '/api/host.describe',
  '/api/workspace.list',
  '/api/session.list',
  '/api/session.create',
  '/api/session.history',
  '/api/session.attachment',
  '/api/session.models',
  '/api/session.selectModel',
  '/api/session.prompt',
  '/api/session.updateQueue',
  '/api/session.cancel',
  '/api/fileReferences/list',
  '/api/sessionReferenceResolver/candidates',
  '/api/subagent.list',
  '/api/subagent.history',
  '/api/subagent.prompt',
  '/api/subagent.interrupt',
  '/api/respond',
]

async function lanRemoteAllowedHttpPaths(): Promise<string[]> {
  const source = await readFile(join(process.cwd(), 'scripts', 'lan-remote-proxy.mjs'), 'utf8')
  const expression = source.match(/const ALLOWED_HTTP_PATHS = (new Set\(\[[\s\S]*?\]\))/)?.[1]
  assert.ok(expression, 'LAN Remote HTTP allowlist declaration is missing')
  return [...runInNewContext(expression)] as string[]
}

async function loadTestApi(): Promise<RemoteTestApi> {
  const source = await readFile(join(process.cwd(), 'src', 'remote.js'), 'utf8')
  const context: Record<string, unknown> = {
    URLSearchParams,
    __DSH_REMOTE_TEST__: true,
  }
  runInNewContext(source, context)
  return context.__DSH_REMOTE_TEST_API__ as RemoteTestApi
}

async function loadLanRemoteProxyApi(): Promise<LanRemoteProxyTestApi> {
  const url = pathToFileURL(join(process.cwd(), 'scripts', 'lan-remote-proxy.mjs'))
  url.searchParams.set('test', `${process.pid}-${Date.now()}`)
  return await import(url.href) as LanRemoteProxyTestApi
}

async function listenOnLoopback(server: Server): Promise<number> {
  await new Promise<void>((resolve, reject) => {
    const onError = (error: Error) => reject(error)
    server.once('error', onError)
    server.listen(0, '127.0.0.1', () => {
      server.off('error', onError)
      resolve()
    })
  })
  return (server.address() as AddressInfo).port
}

async function closeServer(server: Server): Promise<void> {
  if (!server.listening) return
  await new Promise<void>((resolve, reject) => {
    server.close(error => error ? reject(error) : resolve())
  })
}

async function post(
  port: number,
  path: string,
  token: string,
  body?: Buffer,
  declaredLength?: number,
): Promise<{ body: string; status: number }> {
  return await new Promise((resolve, reject) => {
    const request = http.request({
      hostname: '127.0.0.1',
      port,
      method: 'POST',
      path,
      headers: {
        authorization: `Bearer ${token}`,
        'content-type': 'application/json',
        ...(declaredLength === undefined
          ? (body ? { 'content-length': String(body.length) } : {})
          : { 'content-length': String(declaredLength) }),
      },
    }, response => {
      const chunks: Buffer[] = []
      response.on('data', chunk => chunks.push(Buffer.from(chunk)))
      response.on('end', () => resolve({
        body: Buffer.concat(chunks).toString('utf8'),
        status: response.statusCode ?? 0,
      }))
    })
    request.once('error', reject)
    request.end(body)
  })
}

test('Remote actions use the tokenized Desktop bridge', async () => {
  const api = await loadTestApi()
  assert.equal(
    api.actionUrl('remote-enable', 'desktop-token'),
    'dsh-desktop://action/remote-enable?token=desktop-token',
  )
  assert.equal(
    api.actionUrl('remote-disable', 'desktop-token'),
    'dsh-desktop://action/remote-disable?token=desktop-token',
  )
  assert.equal(
    api.actionUrl('remote-open-https', 'desktop-token'),
    'dsh-desktop://action/remote-open-https?token=desktop-token',
  )
  assert.equal(
    api.actionUrl('remote-lan-enable', 'desktop-token'),
    'dsh-desktop://action/remote-lan-enable?token=desktop-token',
  )
  assert.equal(
    api.actionUrl('remote-lan-disable', 'desktop-token'),
    'dsh-desktop://action/remote-lan-disable?token=desktop-token',
  )
  assert.equal(
    api.actionUrl('remote-lan-reset', 'desktop-token'),
    'dsh-desktop://action/remote-lan-reset?token=desktop-token',
  )
  assert.equal(
    api.actionUrl('remote-status', 'desktop-token', { force: 1 }),
    'dsh-desktop://action/remote-status?token=desktop-token&force=1',
  )
  assert.equal(
    api.actionUrl('remote-presented', 'desktop-token', { id: 17 }),
    'dsh-desktop://action/remote-presented?token=desktop-token&id=17',
  )
  assert.throws(() => api.actionUrl('serve-reset', 'desktop-token'))
})

test('Remote state defaults closed and normalizes native payloads', async () => {
  const api = await loadTestApi()
  const initial = api.normalizeStatus()
  assert.equal(initial.statusReady, false)
  assert.equal(initial.tailscaleStatusReady, false)
  assert.equal(initial.enabled, false)
  assert.equal(initial.busy, false)
  assert.equal(initial.port, 8443)
  assert.equal(initial.lanEnabled, false)
  assert.equal(initial.lanPort, 8765)

  const active = api.normalizeStatus({
    enabled: true,
    httpsReady: true,
    url: 'https://dsh-mac.example.ts.net:8443/',
    pairingURL: 'dshremote://connect?url=example',
  })
  assert.equal(active.enabled, true)
  assert.equal(active.statusReady, true)
  assert.equal(active.tailscaleStatusReady, true)
  assert.equal(active.httpsReady, true)
  assert.equal(active.url, 'https://dsh-mac.example.ts.net:8443/')

  const lan = api.normalizeStatus({
    lanAvailable: true,
    lanEnabled: true,
    lanURL: 'http://192.168.1.20:8765/',
    lanPairingURL: 'harnessremote://connect?url=example&token=secret',
  })
  assert.equal(lan.lanAvailable, true)
  assert.equal(lan.lanEnabled, true)
  assert.equal(lan.lanURL, 'http://192.168.1.20:8765/')
})

test('Remote copy follows the active DSH language', async () => {
  const api = await loadTestApi()
  assert.equal(api.languageFromTag('zh-CN'), 'zh')
  assert.equal(api.languageFromTag('en-US'), 'en')
  assert.equal(api.copyFor('zh').title, '手机 Remote')
  assert.equal(api.copyFor('zh').connect, '连接手机')
  assert.equal(api.copyFor('zh').guideAndroidLink, '下载 Android 版')
  assert.equal(api.copyFor('zh').lanTitle, '同一 Wi-Fi')
  assert.equal(api.copyFor('zh').lanReset, '重置配对')
  assert.match(String(api.copyFor('zh').lanResetBody), /立即失效/)
  assert.match(String(api.copyFor('zh').lanDescription), /无需安装或配置 Tailscale/)
  assert.equal(api.copyFor('zh').tailscaleTitle, '跨网络连接')
  assert.equal(api.copyFor('zh').guide, '设置指南')
  assert.match(String(api.copyFor('zh').guideStepEnableDetail), /不需要手动运行命令/)
  assert.equal(api.copyFor('zh').operationChecking, '检查 Tailscale')
  assert.equal(api.copyFor('zh').operationRestarting, '重启 Harness')
  assert.equal(api.copyFor('zh').operationServing, '启动安全入口')
  assert.equal(api.copyFor('zh').operationPairing, '生成配对码')
  assert.equal(api.copyFor('zh').disableStopping, '关闭安全入口')
  assert.equal(api.copyFor('zh').disableRestarting, '恢复 Harness')
  assert.equal(api.copyFor('zh').confirmInterrupt, '正在运行的任务会中断。')
  assert.match(String(api.copyFor('zh').resumeTakingLong), /重新检查/)
  assert.equal(api.copyFor('en').title, 'Mobile Remote')
  assert.equal(api.copyFor('en').connect, 'Connect phone')
  assert.equal(api.copyFor('en').guideAndroidLink, 'Download for Android')
  assert.equal(api.copyFor('en').lanBadge, 'Recommended')
  assert.equal(api.copyFor('en').lanReset, 'Reset pairing')
  assert.equal(api.copyFor('en').guide, 'Setup guide')
})

test('Tailscale tutorial points to the next detected setup step', async () => {
  const api = await loadTestApi()
  assert.equal(api.tailscaleGuideState(undefined, 'zh').key, 'checking')
  assert.equal(api.tailscaleGuideState({ tailscaleStatusReady: true }, 'zh').key, 'install')
  assert.equal(api.tailscaleGuideState({
    tailscaleStatusReady: true,
    installed: true,
    backendState: 'Stopped',
  }, 'zh').key, 'connect')
  assert.equal(api.tailscaleGuideState({
    tailscaleStatusReady: true,
    installed: true,
    backendState: 'Running',
  }, 'zh').key, 'magicdns')
  assert.equal(api.tailscaleGuideState({
    tailscaleStatusReady: true,
    installed: true,
    backendState: 'Running',
    magicDNS: true,
  }, 'zh').key, 'https')
  const ready = api.tailscaleGuideState({
    tailscaleStatusReady: true,
    installed: true,
    backendState: 'Running',
    magicDNS: true,
    httpsReady: true,
  }, 'zh')
  assert.equal(ready.key, 'ready')
  assert.match(String(ready.title), /准备好/)
})

test('Remote uses one settings entry and keeps transport choices inside the pairing layer', async () => {
  const source = await readFile(join(process.cwd(), 'src', 'remote.js'), 'utf8')
  assert.match(source, /:host\(\[hidden\]\)\{display:none\}/)
  assert.match(source, /row\.append\(heading, settingConnectButton\)/)
  assert.match(source, /class="chooser-routes"/)
  assert.match(source, /querySelector\('\.copy'\)\.hidden = lan/)
  assert.match(source, /button:active:not\(:disabled\)\{transform:scale\(\.97\)\}/)
  assert.match(source, /aria-describedby="dsh-remote-dialog-description"/)
  assert.match(source, /document\.addEventListener\('keydown',[\s\S]*?}, true\)/)
  assert.match(source, /event\.key !== 'Tab'/)
  assert.match(source, /button\.getClientRects\(\)\.length > 0/)
  assert.match(source, /if \(!controls\.includes\(active\)\)/)
  assert.match(source, /class="manager-status dialog-view" role="status" aria-live="polite" aria-atomic="true"/)
  assert.match(source, /class="progress-steps" hidden/)
  assert.match(source, /class="confirm dialog-view" hidden/)
  assert.match(source, /class="dsh-remote-primary confirm-enable"/)
  assert.match(source, /class="dsh-remote-danger reset"/)
  assert.match(source, /openLanResetConfirmation/)
  assert.match(source, /class="tailscale-guide dialog-view"/)
  assert.match(source, /openTailscaleGuide/)
  assert.match(source, /https:\/\/tailscale\.com\/download\/mac/)
  assert.match(source, /https:\/\/tailscale\.com\/download\/ios/)
  assert.doesNotMatch(source, /guideStepEnableDetail[^\n]*tailscale serve --/i)
  assert.match(source, /className = 'dsh-remote-spinner'/)
  assert.match(source, /route\.setAttribute\('aria-busy', String\(view\.busy\)\)/)
  assert.match(source, /@media\(prefers-reduced-motion:reduce\)/)
  assert.match(source, /\.dsh-remote-spinner,\.progress-step\[data-state="current"\]::before\{animation:none\}/)
  assert.match(source, /const surfaceVisible = Boolean\(settingRow\?\.isConnected\)[\s\S]*?Boolean\(layer && !layer\.hidden\)[\s\S]*?Boolean\(resumeCurtain\?\.isConnected\)/)
  assert.match(source, /request\('remote-presented', \{ id: operationId \}\)/)
  assert.match(source, /const RESUME_STALL_TIMEOUT_MS = 12000/)
  assert.match(source, /copyFor\(currentLanguage\(\)\)/)
  assert.match(source, /updateResumeCurtainCopy\(\)/)
  assert.match(source, /authoritativeOperationOutcome\(operation, nextStatus\)/)
  assert.match(source, /!operationResumeSettled[\s\S]*?shouldRestoreOperation\(resumeOperationId, operation\)/)
  assert.match(source, /if \(settingRow && settingTitle && settingDescription && settingConnectButton\)/)
  assert.doesNotMatch(source, /function updateSetting\(\) \{\s*if \(!settingRow/)
  assert.match(
    source,
    /if \(!operation\.active && shouldPresent\) \{[\s\S]*?if \(shouldDeferTerminalPresentation\(resumeOperationId, operation\)\)[\s\S]*?if \(dismissedOperationId === operation\.id\)/,
  )
  assert.doesNotMatch(source, /if \(!wasEnabled && status\.enabled\) openPairing\(\)/)
})

test('Remote cold hydration presents independent loading states for LAN and Tailscale', async () => {
  const api = await loadTestApi()
  const coldLan = api.transportViewState(undefined, 'lan', 'zh')
  const coldTailscale = api.transportViewState(undefined, 'tailscale', 'zh')

  assert.equal(coldLan.checking, true)
  assert.equal(coldLan.busy, true)
  assert.equal(coldLan.actionDisabled, true)
  assert.equal(coldLan.description, '正在检查本地连接能力…')
  assert.equal(coldTailscale.checking, true)
  assert.equal(coldTailscale.busy, true)
  assert.equal(coldTailscale.actionDisabled, true)
  assert.equal(coldTailscale.description, '正在检查 Tailscale 状态…')

  const localReady = {
    statusReady: true,
    tailscaleStatusReady: false,
    lanAvailable: true,
  }
  const readyLan = api.transportViewState(localReady, 'lan', 'zh')
  const checkingTailscale = api.transportViewState(localReady, 'tailscale', 'zh')

  assert.equal(readyLan.checking, false)
  assert.equal(readyLan.busy, false)
  assert.equal(readyLan.actionDisabled, false)
  assert.match(String(readyLan.description), /无需安装或配置 Tailscale/)
  assert.equal(checkingTailscale.checking, true)
  assert.equal(checkingTailscale.actionDisabled, true)
  assert.equal(checkingTailscale.description, '正在检查 Tailscale 状态…')
})

test('Remote operation stages normalize into a stable progress contract', async () => {
  const api = await loadTestApi()
  const cases = [
    ['checking-tailscale', 'checking', 0, ''],
    ['restarting-harness', 'restarting', 1, ''],
    ['starting-serve', 'serving', 2, ''],
    ['creating-pairing-code', 'pairing', 3, ''],
    ['restoring-harness', 'restarting', 1, ''],
    ['stopping-serve', 'serving', 2, ''],
    ['ready', 'ready', 4, 'ready'],
  ] as const

  for (const [stage, normalizedStage, stepIndex, terminal] of cases) {
    assert.equal(api.normalizedOperationStage(stage), normalizedStage)
    const progress = api.operationProgress({
      id: 41,
      transport: 'tailscale',
      action: stage === 'stopping-serve' ? 'disable' : 'enable',
      stage,
      active: terminal === '',
    })
    assert.equal(progress.normalizedStage, normalizedStage)
    assert.equal(progress.stepIndex, stepIndex)
    assert.equal(progress.terminal, terminal)
  }

  const failed = api.operationProgress({
    id: 41,
    transport: 'tailscale',
    action: 'enable',
    stage: 'failed',
    active: false,
    error: 'Serve failed',
  })
  assert.equal(failed.normalizedStage, 'error')
  assert.equal(failed.stepIndex, -1, 'errors must not pretend that a progress step failed')
  assert.equal(failed.terminal, 'error')
})

test('authoritative transport readiness finishes a stale Remote operation', async () => {
  const api = await loadTestApi()
  const enabling = {
    id: '71',
    transport: 'tailscale',
    action: 'enable',
    stage: 'generating-pairing',
    active: true,
  }
  assert.equal(api.authoritativeOperationOutcome(enabling, {
    statusReady: true,
    enabled: true,
    qrSvg: 'data:image/svg+xml,ready',
  }), 'enable-ready')
  assert.equal(api.authoritativeOperationOutcome(enabling, {
    statusReady: true,
    enabled: true,
    qrSvg: '',
  }), '')

  const disabling = {
    id: '72',
    transport: 'tailscale',
    action: 'disable',
    stage: 'restoring-harness',
    active: true,
  }
  assert.equal(api.authoritativeOperationOutcome(disabling, {
    statusReady: true,
    enabled: false,
    busy: false,
  }), 'disable-ready')
})

test('Remote presentation resumes only the exact native operation', async () => {
  const api = await loadTestApi()
  const operations = [
    { id: 51, transport: 'tailscale', action: 'enable', stage: 'restarting-harness', active: true },
    { id: 52, transport: 'tailscale', action: 'disable', stage: 'restoring-harness', active: true },
    {
      id: 53,
      transport: 'tailscale',
      action: 'enable',
      stage: 'failed',
      active: false,
      error: 'Serve failed',
    },
  ]

  for (const operation of operations) {
    assert.equal(api.shouldRestoreOperation(String(operation.id), operation), true)
    assert.equal(api.shouldRestoreOperation(String(operation.id + 1), operation), false)
    assert.equal(api.shouldRestoreOperation('', operation), false)
  }

  const handedOff = {
    id: 54,
    transport: 'tailscale',
    action: 'enable',
    stage: 'ready',
    active: false,
    presentationHandoffReady: true,
  }
  assert.equal(api.shouldDeferTerminalPresentation('', handedOff), true)
  assert.equal(api.shouldDeferTerminalPresentation('53', handedOff), true)
  assert.equal(api.shouldDeferTerminalPresentation('54', handedOff), false)
  assert.equal(
    api.shouldDeferTerminalPresentation('', { ...handedOff, presentationHandoffReady: false }),
    false,
    'a failed or missing native navigation must keep terminal recovery on the current page',
  )

  const ordinaryHydration = api.normalizeStatus({
    statusReady: true,
    tailscaleStatusReady: true,
    enabled: true,
    qrSvg: 'data:image/svg+xml,ready',
  })
  assert.equal(
    api.shouldRestoreOperation('51', ordinaryHydration.operation as Record<string, unknown>),
    false,
    'an already-enabled status without an operation must not auto-present pairing',
  )
})

test('LAN pairing auto-opens for a requested enable or credential rotation', async () => {
  const api = await loadTestApi()
  const off = { statusReady: true, lanAvailable: true, lanEnabled: false }
  const on = {
    statusReady: true,
    lanEnabled: true,
    lanQrSvg: 'data:image/svg+xml,lan',
    lanPairingURL: 'harnessremote://connect?token=first',
  }
  const rotated = {
    ...on,
    lanQrSvg: 'data:image/svg+xml,rotated',
    lanPairingURL: 'harnessremote://connect?token=second',
  }

  assert.equal(api.shouldAutoOpenLanPairing(false, off, on), false)
  assert.equal(api.shouldAutoOpenLanPairing(true, off, { ...on, lanQrSvg: '' }), false)
  assert.equal(api.shouldAutoOpenLanPairing(true, on, on), false)
  assert.equal(api.shouldAutoOpenLanPairing(true, off, on), true)
  assert.equal(api.shouldAutoOpenLanPairing(true, on, rotated), true)
  assert.equal(
    api.pendingActionAfterStatus('remote-lan-enable', { lanBusy: true }, 'lan'),
    '',
    'native busy acknowledges the requested LAN transition while its operation continues',
  )
  assert.equal(
    api.pendingActionAfterStatus('remote-lan-reset', { lanBusy: false, lanEnabled: true }, 'lan'),
    '',
    'credential rotation completes without changing the enabled state',
  )
})

test('Remote transports block conflicting operations without borrowing the busy label', async () => {
  const api = await loadTestApi()
  const ready = {
    statusReady: true,
    tailscaleStatusReady: true,
    lanAvailable: true,
    installed: true,
    backendState: 'Running',
    magicDNS: true,
    httpsReady: true,
  }
  const lanBlocked = api.transportViewState({
    ...ready,
    operation: {
      id: 61,
      transport: 'tailscale',
      action: 'enable',
      stage: 'restarting-harness',
      active: true,
    },
  }, 'lan', 'zh')
  assert.equal(lanBlocked.blocked, true)
  assert.equal(lanBlocked.busy, false)
  assert.equal(lanBlocked.actionDisabled, true)

  const tailscaleBlocked = api.transportViewState(
    { ...ready, lanBusy: true },
    'tailscale',
    'zh',
    '',
    'remote-lan-enable',
  )
  assert.equal(tailscaleBlocked.blocked, true)
  assert.equal(tailscaleBlocked.busy, false)
  assert.equal(tailscaleBlocked.actionDisabled, true)
})

test('LAN remains the available primary path when Tailscale is unavailable', async () => {
  const api = await loadTestApi()
  const status = {
    lanAvailable: true,
    installed: false,
    backendState: 'Stopped',
    error: 'Tailscale is not installed',
  }
  const lan = api.transportViewState(status, 'lan', 'zh')
  const tailscale = api.transportViewState(status, 'tailscale', 'zh')

  assert.equal(lan.action, 'remote-lan-enable')
  assert.equal(lan.actionDisabled, false)
  assert.match(String(lan.description), /无需安装或配置 Tailscale/)
  assert.equal(lan.hasError, false)
  assert.equal(tailscale.actionDisabled, true)
  assert.equal(tailscale.description, 'Tailscale is not installed')
  assert.equal(tailscale.hasError, true)
})

test('Remote transport errors and busy labels stay isolated', async () => {
  const api = await loadTestApi()
  const initial = {
    installed: true,
    backendState: 'Running',
    magicDNS: true,
    httpsReady: true,
    busy: true,
    lanBusy: true,
    error: 'tailnet failed',
    lanError: 'local network failed',
  }

  const lanFailure = api.statusAfterError(initial, 'lan', 'new local error')
  assert.equal(lanFailure.lanBusy, false)
  assert.equal(lanFailure.lanError, 'new local error')
  assert.equal(lanFailure.busy, true)
  assert.equal(lanFailure.error, 'tailnet failed')

  const tailscaleFailure = api.statusAfterError(initial, 'tailscale', 'new tailnet error')
  assert.equal(tailscaleFailure.busy, false)
  assert.equal(tailscaleFailure.error, 'new tailnet error')
  assert.equal(tailscaleFailure.lanBusy, true)
  assert.equal(tailscaleFailure.lanError, 'local network failed')

  const localPending = api.transportViewState(
    { lanAvailable: true },
    'lan',
    'zh',
    'remote-lan-enable',
  )
  assert.equal(localPending.busy, true)
  assert.equal(localPending.actionDisabled, true)
  assert.equal(localPending.description, '正在准备本地连接…')

  assert.equal(
    api.pendingActionAfterStatus('remote-lan-enable', { lanAvailable: true }, 'lan'),
    'remote-lan-enable',
    'an older poll response must not clear optimistic LAN busy state',
  )
  assert.equal(
    api.pendingActionAfterStatus('remote-lan-enable', { lanBusy: true }, 'lan'),
    '',
    'native busy state acknowledges the LAN action',
  )
  assert.equal(
    api.pendingActionAfterStatus('remote-enable', { enabled: true }, 'tailscale'),
    '',
    'the completed target state acknowledges the Tailscale action',
  )
})

test('Remote status polling is visible, idle, and single-flight', async () => {
  const api = await loadTestApi()
  assert.equal(api.shouldPollStatus(undefined, false), false)
  assert.equal(
    api.shouldPollStatus(undefined, true),
    true,
    'an open manager or resume curtain must be able to hydrate before the setting row mounts',
  )
  assert.equal(api.shouldPollStatus({ backendState: 'Stopped', error: 'not connected' }, true), true)
  assert.equal(api.shouldPollStatus({
    backendState: 'Running',
    magicDNS: true,
    httpsReady: true,
  }, true), true)
  assert.equal(api.shouldPollStatus({ busy: true }, true), false)
  assert.equal(api.shouldPollStatus({ lanBusy: true }, true), false)
  assert.equal(api.shouldPollStatus({}, true, false), false)
  assert.equal(api.shouldPollStatus({}, true, true, true), false)
})

test('Remote DOM observer does not schedule mounts for its own text updates', async () => {
  const source = await readFile(join(process.cwd(), 'src', 'remote.js'), 'utf8')
  assert.match(source, /new MutationObserver\(handleMutations\)/)
  assert.doesNotMatch(source, /new MutationObserver\(scheduleMount\)/)
  assert.match(source, /settingRow\.parentElement !== slot\)\) scheduleMount\(\)/)
})

test('Desktop retries authoritative Remote status after internal navigation', async () => {
  const native = await readFile(join(process.cwd(), 'src-tauri', 'src', 'main.rs'), 'utf8')
  assert.match(native, /const REMOTE_HANDOFF_STATUS_DELAYS: \[Duration; 3\]/)
  assert.match(native, /fn schedule_remote_handoff_status\(handle: tauri::AppHandle\)/)
  assert.match(
    native,
    /mark_remote_operation_presentation_handoff\(&mut state, operation_id\);[\s\S]*?emit_remote_status\(handle\);[\s\S]*?schedule_remote_handoff_status\(handle\.clone\(\)\);/,
  )
})

test('LAN Remote HTTP allowlist exactly matches the reviewed capability boundary', async () => {
  const paths = await lanRemoteAllowedHttpPaths()
  assert.deepEqual(paths, EXPECTED_LAN_REMOTE_HTTP_PATHS)
})

test('LAN Remote exposes only the reviewed references and subagent capabilities', async () => {
  const paths = await lanRemoteAllowedHttpPaths()
  assert.ok(paths.includes('/api/session.attachment'))

  for (const path of [
    '/api/fileReferences/list',
    '/api/sessionReferenceResolver/candidates',
    '/api/subagent.list',
    '/api/subagent.history',
    '/api/subagent.prompt',
    '/api/subagent.interrupt',
  ]) {
    assert.ok(paths.includes(path), `${path} must be available to LAN Remote`)
  }

  for (const path of [
    '/api/events.host',
    '/api/settings.describe',
    '/api/settings.update',
    '/api/settings.write',
    '/api/credentials.describe',
    '/api/credentials.set',
    '/api/host.pickDirectory',
    '/api/host.listDirectory',
    '/api/host.createDirectory',
    '/api/host.openPath',
    '/api/workspace.create',
    '/api/workspace.delete',
  ]) {
    assert.equal(paths.includes(path), false, `${path} must stay outside LAN Remote`)
  }
})

test('LAN Remote validates the 136 MiB wire limit without the former 2 MiB cap', async () => {
  const api = await loadLanRemoteProxyApi()
  const mebibyte = 1024 * 1024
  const aboveOldLimit = 2 * mebibyte + 1
  const hostDefaultImageWireBytes = 4 * Math.ceil((100 * mebibyte) / 3) + mebibyte

  assert.equal(api.MAX_BODY_BYTES, 136 * mebibyte)
  assert.ok(hostDefaultImageWireBytes <= api.MAX_BODY_BYTES)
  assert.deepEqual(api.inspectDeclaredBodyLength(String(aboveOldLimit)), {
    status: 'ok',
    bytes: aboveOldLimit,
  })
  assert.deepEqual(api.inspectDeclaredBodyLength(String(api.MAX_BODY_BYTES)), {
    status: 'ok',
    bytes: api.MAX_BODY_BYTES,
  })
  assert.equal(
    api.inspectDeclaredBodyLength(String(api.MAX_BODY_BYTES + 1)).status,
    'too-large',
  )
  assert.equal(api.streamedBodyExceedsLimit(aboveOldLimit), false)
  assert.equal(api.streamedBodyExceedsLimit(api.MAX_BODY_BYTES), false)
  assert.equal(api.streamedBodyExceedsLimit(api.MAX_BODY_BYTES + 1), true)

  for (const invalid of ['', '-1', '1e3', 'Infinity', ['1', '2']]) {
    assert.equal(api.inspectDeclaredBodyLength(invalid).status, 'invalid')
  }
})

test('LAN Remote streams with backpressure and stops before forwarding an overflow chunk', async () => {
  const api = await loadLanRemoteProxyApi()
  const acceptedSource = new PassThrough()
  let acceptedBytes = 0
  const acceptedDestination = new Writable({
    write(chunk: Buffer, _encoding, callback) {
      acceptedBytes += chunk.length
      callback()
    },
  })
  const accepted = api.forwardRequestBody(acceptedSource, acceptedDestination, 3 * 1024 * 1024)
  acceptedSource.end(Buffer.alloc(2 * 1024 * 1024 + 1))
  assert.equal(await accepted, 2 * 1024 * 1024 + 1)
  assert.equal(acceptedBytes, 2 * 1024 * 1024 + 1)

  const rejectedSource = new PassThrough()
  let rejectedBytes = 0
  const rejectedDestination = new Writable({
    write(chunk: Buffer, _encoding, callback) {
      rejectedBytes += chunk.length
      callback()
    },
  })
  const rejected = api.forwardRequestBody(rejectedSource, rejectedDestination, 1024)
  rejectedSource.end(Buffer.alloc(1025))
  await assert.rejects(rejected, error => (
    error instanceof Error && (error as NodeJS.ErrnoException).code === 'BODY_TOO_LARGE'
  ))
  assert.equal(rejectedBytes, 0)
  rejectedDestination.destroy()
})

test('LAN Remote strips credentials, rewrites Host, streams large requests, and rejects declared overflow', async (t) => {
  const api = await loadLanRemoteProxyApi()
  const token = 'a'.repeat(64)
  let upstreamRequests = 0
  let upstreamBytes = 0
  let upstreamHeaders: http.IncomingHttpHeaders | undefined
  const upstreamServer = http.createServer((request, response) => {
    upstreamRequests += 1
    upstreamHeaders = request.headers
    request.on('data', chunk => {
      upstreamBytes += chunk.length
    })
    request.on('end', () => {
      response.writeHead(200, { 'content-type': 'application/json', 'set-cookie': 'secret=1' })
      response.end('{"ok":true}')
    })
  })
  t.after(() => closeServer(upstreamServer))
  const upstreamPort = await listenOnLoopback(upstreamServer)
  const proxyServer = api.createLanRemoteServer(new URL(`http://127.0.0.1:${upstreamPort}`), token)
  t.after(() => closeServer(proxyServer))
  const proxyPort = await listenOnLoopback(proxyServer)

  const body = Buffer.alloc(2 * 1024 * 1024 + 1)
  const accepted = await post(proxyPort, '/api/session.prompt', token, body)
  assert.equal(accepted.status, 200)
  assert.equal(accepted.body, '{"ok":true}')
  assert.equal(upstreamRequests, 1)
  assert.equal(upstreamBytes, body.length)
  assert.equal(upstreamHeaders?.authorization, undefined)
  assert.equal(upstreamHeaders?.cookie, undefined)
  assert.equal(upstreamHeaders?.host, `127.0.0.1:${upstreamPort}`)
  assert.equal(upstreamHeaders?.['content-length'], String(body.length))

  const rejected = await post(
    proxyPort,
    '/api/session.prompt',
    token,
    undefined,
    api.MAX_BODY_BYTES + 1,
  )
  assert.equal(rejected.status, 413)
  assert.equal(upstreamRequests, 1, 'declared overflow must be rejected before connecting upstream')

  const headers = api.proxyHeaders({
    headers: {
      accept: 'application/json',
      authorization: `Bearer ${token}`,
      connection: 'keep-alive',
      cookie: 'secret=1',
      expect: '100-continue',
      'proxy-authorization': 'Basic secret',
      'transfer-encoding': 'chunked',
    },
  }, new URL(`http://127.0.0.1:${upstreamPort}`), body.length)
  assert.deepEqual(headers, {
    accept: 'application/json',
    host: `127.0.0.1:${upstreamPort}`,
    'content-length': String(body.length),
  })
})

test('iOS Remote ships complete English and Simplified Chinese product-copy coverage', async () => {
  const iosRoot = join(process.cwd(), 'ios', 'DSHRemote', 'DSHRemote')
  const englishPath = join(iosRoot, 'en.lproj', 'Localizable.strings')
  const chinesePath = join(iosRoot, 'zh-Hans.lproj', 'Localizable.strings')
  const projectPath = join(process.cwd(), 'ios', 'DSHRemote', 'DSHRemote.xcodeproj', 'project.pbxproj')
  const [englishSource, chineseSource, projectSource, relativePaths] = await Promise.all([
    readFile(englishPath, 'utf8'),
    readFile(chinesePath, 'utf8'),
    readFile(projectPath, 'utf8'),
    readdir(iosRoot, { recursive: true }),
  ])

  const entryPattern = /^"((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)";/gm
  const englishEntries = [...englishSource.matchAll(entryPattern)]
  const english = new Map<string, string>()
  for (const entry of englishEntries) {
    const key = entry[1]
    const value = entry[2]
    assert.ok(key !== undefined && value !== undefined)
    assert.equal(english.has(key), false, `duplicate English localization key: ${key}`)
    english.set(key, value)
    assert.doesNotMatch(value, /[\u3400-\u9fff]/, `English value still contains Han text: ${key}`)
  }
  assert.ok(english.size >= 640, 'the English catalog should cover the complete Remote surface')

  const placeholderTokens = (value: string): string[] => (
    [...value.matchAll(/%(?:\d+\$)?(?:\.\d+)?(?:lld|ld|d|@|f|%)/g)]
      .map(match => match[0].replace(/%\d+\$/, '%'))
      .filter(token => token !== '%%')
      .sort()
  )
  for (const [key, value] of english) {
    if (!key.includes('%')) continue
    assert.deepEqual(
      placeholderTokens(value),
      placeholderTokens(key),
      `localization placeholders changed for: ${key}`,
    )
  }

  const swiftPaths = relativePaths
    .map(String)
    .filter(path => path.endsWith('.swift'))
  const chineseLiteral = /"((?:\\.|[^"\\])*[\u3400-\u9fff](?:\\.|[^"\\])*)"/g
  const untranslated: string[] = []
  for (const relativePath of swiftPaths) {
    const source = await readFile(join(iosRoot, relativePath), 'utf8')
    for (const match of source.matchAll(chineseLiteral)) {
      const literal = match[1]
      assert.ok(literal !== undefined)
      if (!english.has(literal)) untranslated.push(`${relativePath}: ${literal}`)
    }
  }
  assert.deepEqual(untranslated, [], 'every Chinese product-copy literal needs an English value')

  assert.match(projectSource, /knownRegions = \([\s\S]*en,[\s\S]*"zh-Hans"/)
  assert.match(projectSource, /en\.lproj\/Localizable\.strings/)
  assert.match(projectSource, /zh-Hans\.lproj\/Localizable\.strings/)
  assert.match(chineseSource, /"count\.project\.one" = "%lld 个项目";/)

  const designSystem = await readFile(join(iosRoot, 'Views', 'RemoteDesignSystem.swift'), 'utf8')
  assert.match(designSystem, /Text\(remoteLocalized\(title\)\)/)
  assert.match(designSystem, /Text\(remoteLocalized\(message\)\)/)
  assert.match(designSystem, /Text\(remoteLocalized\(detail\)\)/)

  const conversation = await readFile(join(iosRoot, 'Views', 'RemoteConversationView.swift'), 'utf8')
  assert.match(conversation, /return remoteLocalized\(title\)/)
  assert.match(conversation, /Text\(remoteLocalized\(record\.title\)\)/)
  assert.match(conversation, /accessibilityHint = remoteLocalized\("使用放大和缩小操作调整图片"\)/)
})

test('Remote v1 contract fixtures stay aligned with the reviewed mobile boundary', async () => {
  const fixtureRoot = join(process.cwd(), 'test', 'fixtures', 'remote-v1')
  const contract = await readFile(join(process.cwd(), 'docs', 'REMOTE_PROTOCOL_V1.md'), 'utf8')
  const fixtureNames = (await readdir(fixtureRoot)).filter(name => name.endsWith('.json')).sort()

  assert.deepEqual(fixtureNames, [
    'events.approval-requested.json',
    'events.question-requested.json',
    'events.queue.json',
    'host-describe.request.json',
    'host-describe.response.json',
    'session-list.response.json',
  ])

  const fixtures = await Promise.all(fixtureNames.map(async name => ({
    name,
    value: JSON.parse(await readFile(join(fixtureRoot, name), 'utf8')) as Record<string, unknown>,
  })))
  for (const fixture of fixtures) {
    assert.equal(typeof fixture.value.rpcId, 'string', `${fixture.name} needs an rpcId`)
  }

  const request = fixtures.find(fixture => fixture.name === 'host-describe.request.json')?.value
  assert.deepEqual(request, {
    type: 'client-request',
    rpcId: 'fixture-host-describe',
    method: 'host.describe',
    payload: {},
  })

  for (const path of EXPECTED_LAN_REMOTE_HTTP_PATHS) {
    const method = path.replace('/api/', '')
    assert.ok(contract.includes('`' + method + '`'), `contract is missing ${method}`)
  }
  assert.match(contract, /The only upgrade route is `events\.mux`/)

  const eventTypes = fixtures
    .filter(fixture => fixture.name.startsWith('events.'))
    .map(fixture => {
      const payload = fixture.value.payload as Record<string, unknown>
      return payload.type
    })
    .sort()
  assert.deepEqual(eventTypes, [
    'approval/requested',
    'question/requested',
    'session/queue',
  ])
})

test('Android Remote keeps its build, security boundary, protocol, and locales in sync', async () => {
  const androidRoot = join(process.cwd(), 'android')
  const appRoot = join(androidRoot, 'app')
  const [build, manifest, englishSource, chineseSource, clientSource] = await Promise.all([
    readFile(join(appRoot, 'build.gradle.kts'), 'utf8'),
    readFile(join(appRoot, 'src', 'main', 'AndroidManifest.xml'), 'utf8'),
    readFile(join(appRoot, 'src', 'main', 'res', 'values', 'strings.xml'), 'utf8'),
    readFile(join(appRoot, 'src', 'main', 'res', 'values-zh-rCN', 'strings.xml'), 'utf8'),
    readFile(join(
      appRoot,
      'src',
      'main',
      'java',
      'com',
      'chokwinlee',
      'dshremote',
      'remote',
      'LiveHarnessRemoteClient.kt',
    ), 'utf8'),
  ])

  assert.match(build, /namespace = "com\.chokwinlee\.dshremote"/)
  assert.match(build, /applicationId = "com\.chokwinlee\.dshremote"/)
  assert.match(build, /compileSdk = 37/)
  assert.match(build, /minSdk = 26/)
  assert.match(build, /com\.google\.mlkit:barcode-scanning:17\.3\.0/)
  assert.match(build, /androidx\.exifinterface:exifinterface:1\.4\.2/)

  assert.match(manifest, /android\.permission\.CAMERA/)
  assert.match(manifest, /android\.permission\.ACCESS_LOCAL_NETWORK/)
  assert.match(manifest, /android\.permission\.POST_NOTIFICATIONS/)
  assert.match(manifest, /android:allowBackup="false"/)
  assert.match(manifest, /android:dataExtractionRules="@xml\/data_extraction_rules"/)
  assert.match(manifest, /android:scheme="harnessremote"/)
  assert.match(manifest, /android:scheme="dshremote"/)

  const resourceNames = (source: string): string[] => [
    ...source.matchAll(/<(?:string|plurals)\s+name="([^"]+)"/g),
  ].map(match => match[1] ?? '').filter(Boolean).sort()
  const englishNames = resourceNames(englishSource)
  const chineseNames = resourceNames(chineseSource)
  assert.ok(englishNames.length >= 290, 'Android Remote should localize its complete product surface')
  assert.deepEqual(chineseNames, englishNames, 'Android locale resource names must stay identical')

  const androidMainJava = join(appRoot, 'src', 'main', 'java')
  const androidKotlinPaths = (await readdir(androidMainJava, { recursive: true }))
    .map(String)
    .filter(path => path.endsWith('.kt'))
  const hardcodedHan: string[] = []
  for (const relativePath of androidKotlinPaths) {
    const source = await readFile(join(androidMainJava, relativePath), 'utf8')
    if (/[\u3400-\u9fff]/.test(source)) hardcodedHan.push(relativePath)
  }
  assert.deepEqual(hardcodedHan, [], 'Android product copy belongs in localized resources')

  for (const path of EXPECTED_LAN_REMOTE_HTTP_PATHS) {
    const method = path.replace('/api/', '')
    assert.ok(
      clientSource.includes(`"${method}"`) || clientSource.includes(`"api/${method}"`),
      `Android client is missing ${method}`,
    )
  }
  assert.match(clientSource, /events\.mux/)
  assert.match(clientSource, /Authorization/)
  assert.match(clientSource, /Bearer/)
})

test('tagged releases require a signed installable Android APK', async () => {
  const [workflow, ciWorkflow, dependabot, wrapper, build, readme, readmeChinese, signingGuide] = await Promise.all([
    readFile(join(process.cwd(), '.github', 'workflows', 'release.yml'), 'utf8'),
    readFile(join(process.cwd(), '.github', 'workflows', 'ci.yml'), 'utf8'),
    readFile(join(process.cwd(), '.github', 'dependabot.yml'), 'utf8'),
    readFile(join(process.cwd(), 'android', 'gradle', 'wrapper', 'gradle-wrapper.properties'), 'utf8'),
    readFile(join(process.cwd(), 'android', 'app', 'build.gradle.kts'), 'utf8'),
    readFile(join(process.cwd(), 'README.md'), 'utf8'),
    readFile(join(process.cwd(), 'README.zh-CN.md'), 'utf8'),
    readFile(join(process.cwd(), 'docs', 'ANDROID_RELEASE_SIGNING.md'), 'utf8'),
  ])

  assert.match(workflow, /name: Release desktop installers and Android companion/)
  assert.match(workflow, /\n  release-guard:\n/)
  assert.match(workflow, /fetch-depth: 0/)
  assert.match(workflow, /git merge-base --is-ancestor "\$tag_commit" refs\/remotes\/origin\/main/)
  assert.match(workflow, /environment: android-release/)
  assert.match(workflow, /\n  android:\n/)
  for (const secret of [
    'ANDROID_KEYSTORE_BASE64',
    'ANDROID_KEYSTORE_PASSWORD',
    'ANDROID_KEY_ALIAS',
    'ANDROID_KEY_PASSWORD',
  ]) {
    assert.match(workflow, new RegExp(`secrets\\.${secret}`))
  }
  assert.match(workflow, /assembleRelease/)
  assert.match(workflow, /bundleRelease/)
  assert.match(workflow, /lintRelease/)
  assert.match(workflow, /validateDebugScreenshotTest/)
  assert.match(workflow, /verifyReleaseVersionCodeOrdering/)
  assert.match(workflow, /bundletool-all-1\.18\.2\.jar/)
  assert.match(workflow, /java -jar "\$bundletool" validate --bundle="\$aab"/)
  assert.match(workflow, /grep -Fq 'PAGE_ALIGNMENT_16K'/)
  assert.match(workflow, /zipalign" -c -P 16 4 "\$apk"/)
  assert.match(workflow, /verify --verbose --print-certs "\$apk"/)
  assert.match(workflow, /jarsigner .* -verify "\$aab"/)
  assert.match(workflow, /keytool .* -printcert -jarfile "\$aab"/)
  assert.match(workflow, /test "\$apk_cert" = "\$aab_cert"/)
  assert.match(
    workflow,
    /expected_cert='521cef4ba06c39a5b704f55d13109c918f43358dd8af530701c73e793c293aaa'/,
  )
  assert.match(workflow, /test "\$apk_cert" = "\$expected_cert"/)
  assert.doesNotMatch(workflow, /jarsigner -verify -strict/)
  for (const actionsWorkflow of [workflow, ciWorkflow]) {
    assert.doesNotMatch(actionsWorkflow, /uses: [^\n]+@v\d+/)
  }
  assert.match(workflow, /release_args\+=\(--prerelease\)/)
  assert.match(workflow, /DSH-Remote-Android-\$\{GITHUB_REF_NAME\}\.apk/)
  assert.match(workflow, /name: installers-android/)
  assert.match(workflow, /name: play-bundle-android/)
  assert.match(workflow, /needs: \[release-guard, macos, windows, android\]/)
  assert.match(workflow, /publish:[\s\S]*permissions:\n\s+contents: write/)

  const qualityGateIndex = workflow.indexOf('- name: Verify Android quality gates')
  const signingIndex = workflow.indexOf('- name: Configure Android release signing')
  const releaseBuildIndex = workflow.indexOf('- name: Build and verify Android Remote')
  assert.ok(qualityGateIndex > -1 && qualityGateIndex < signingIndex)
  assert.ok(signingIndex < releaseBuildIndex)
  assert.doesNotMatch(
    workflow.slice(qualityGateIndex, signingIndex),
    /DSH_RELEASE_VERSION/,
    'screenshot validation must use the stable debug version, not the tagged BuildConfig version',
  )

  assert.match(build, /environmentVariable\("DSH_RELEASE_VERSION"\)/)
  assert.match(build, /fun semverVersionCode\(version: String\)/)
  assert.match(build, /"alpha" -> 1_000 \+ prereleaseNumber!!/)
  assert.match(build, /"beta" -> 3_000 \+ prereleaseNumber!!/)
  assert.match(build, /"rc" -> 5_000 \+ prereleaseNumber!!/)
  assert.match(build, /"" -> 9_000/)
  assert.match(build, /check\(semverVersionCode\("0\.4\.0-beta\.1"\) == 4_003_001\)/)
  assert.match(build, /check\(semverVersionCode\("0\.4\.0"\) == 4_009_000\)/)
  assert.match(build, /environmentVariable\("ANDROID_KEYSTORE_PATH"\)/)
  assert.match(build, /signingConfig = signingConfigs\.getByName\("release"\)/)
  assert.match(
    wrapper,
    /distributionSha256Sum=2ab2958f2a1e51120c326cad6f385153bb11ee93b3c216c5fccebfdfbb7ec6cb/,
  )
  assert.match(dependabot, /package-ecosystem: gradle\n\s+directory: \/android/)

  for (const source of [readme, readmeChinese]) {
    assert.match(source, /DSH-Remote-Android-v0\.4\.0-beta\.1\.apk/)
  }
  assert.match(signingGuide, /same persistent project key/)
  assert.match(signingGuide, /Play App Signing/)
  assert.match(signingGuide, /SHA256SUMS\.txt/)
})
