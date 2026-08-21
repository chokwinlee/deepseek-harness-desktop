import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { join } from 'node:path'
import test from 'node:test'
import { runInNewContext } from 'node:vm'

interface RemoteTestApi {
  actionUrl: (action: string, token?: string) => string
  copyFor: (language: 'zh' | 'en') => Record<string, string>
  languageFromTag: (tag: string) => 'zh' | 'en'
  normalizeStatus: (value?: Record<string, unknown>) => Record<string, unknown>
  shouldPollStatus: (value: Record<string, unknown> | undefined, settingVisible: boolean) => boolean
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
  assert.equal(api.copyFor('en').title, 'Mobile Remote')
})

test('Remote pairing layer preserves an explicit hidden state', async () => {
  const source = await readFile(join(process.cwd(), 'src', 'remote.js'), 'utf8')
  assert.match(source, /:host\(\[hidden\]\)\{display:none\}/)
})

test('Remote polls Tailscale while its settings row is visible', async () => {
  const api = await loadTestApi()
  assert.equal(api.shouldPollStatus(undefined, false), false)
  assert.equal(api.shouldPollStatus({ backendState: 'Stopped', error: 'not connected' }, true), true)
  assert.equal(api.shouldPollStatus({
    backendState: 'Running',
    magicDNS: true,
    httpsReady: true,
  }, true), true)
  assert.equal(api.shouldPollStatus({ busy: true }, true), false)
})

test('LAN Remote HTTP allowlist exactly matches the reviewed capability boundary', async () => {
  const paths = await lanRemoteAllowedHttpPaths()
  assert.deepEqual(paths, EXPECTED_LAN_REMOTE_HTTP_PATHS)
})

test('LAN Remote allows referenced attachments but keeps sensitive host APIs closed', async () => {
  const paths = await lanRemoteAllowedHttpPaths()
  assert.ok(paths.includes('/api/session.attachment'))

  for (const path of [
    '/api/settings.describe',
    '/api/settings.update',
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
