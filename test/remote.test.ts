import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
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
  copyFor: (language: 'zh' | 'en') => Record<string, string>
  languageFromTag: (tag: string) => 'zh' | 'en'
  normalizeStatus: (value?: Record<string, unknown>) => Record<string, unknown>
  pendingActionAfterStatus: (
    pendingAction: string,
    value: Record<string, unknown> | undefined,
    transport: 'lan' | 'tailscale',
  ) => string
  shouldPollStatus: (
    value: Record<string, unknown> | undefined,
    settingVisible: boolean,
    pageVisible?: boolean,
    requestInFlight?: boolean,
  ) => boolean
  statusAfterError: (
    value: Record<string, unknown> | undefined,
    transport: 'lan' | 'tailscale',
    message: string,
  ) => Record<string, unknown>
  transportViewState: (
    value: Record<string, unknown> | undefined,
    transport: 'lan' | 'tailscale',
    language?: 'zh' | 'en',
    pendingAction?: string,
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
    api.actionUrl('remote-status', 'desktop-token', { force: 1 }),
    'dsh-desktop://action/remote-status?token=desktop-token&force=1',
  )
  assert.throws(() => api.actionUrl('serve-reset', 'desktop-token'))
})

test('Remote state defaults closed and normalizes native payloads', async () => {
  const api = await loadTestApi()
  const initial = api.normalizeStatus()
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
  assert.equal(api.copyFor('zh').connect, '连接 iPhone')
  assert.equal(api.copyFor('zh').lanTitle, '同一 Wi-Fi')
  assert.match(String(api.copyFor('zh').lanDescription), /无需安装或配置 Tailscale/)
  assert.equal(api.copyFor('zh').tailscaleTitle, '跨网络连接')
  assert.equal(api.copyFor('en').title, 'Mobile Remote')
  assert.equal(api.copyFor('en').lanBadge, 'Recommended')
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
