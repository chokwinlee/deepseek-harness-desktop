import { join } from 'node:path'
import { pathToFileURL } from 'node:url'
export const UPSTREAM_WELCOME_NOTICE_VERSION = '2026-08-13.1'
const [origin, modulesDirectory] = process.argv.slice(2)
if (!origin || !modulesDirectory) throw new Error('usage: acknowledge-onboarding.mjs ORIGIN NODE_MODULES')
const { connectLoopback, callRemote } = await import(pathToFileURL(join(modulesDirectory, 'dsh-desktop-settings-plugin/lib/rpc.js')).href)
const connection = await connectLoopback(origin)
const described = await callRemote(connection, 'settings/describe', {})
const view = described.namespaces.find(item => item.ns === 'ui-onboarding')
if (!view) throw new Error('Harness onboarding settings are unavailable')
if (view.value?.welcomeNoticeVersion !== UPSTREAM_WELCOME_NOTICE_VERSION) {
  const updated = await callRemote(connection, 'settings/mutate', {
    ns: 'ui-onboarding', ops: [{ op: 'set', path: ['welcomeNoticeVersion'], value: UPSTREAM_WELCOME_NOTICE_VERSION }],
  })
  if (updated.value?.welcomeNoticeVersion !== UPSTREAM_WELCOME_NOTICE_VERSION) throw new Error('Harness did not retain the welcome notice acknowledgement')
}
