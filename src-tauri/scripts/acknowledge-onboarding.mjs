import { join } from 'node:path'
import { pathToFileURL } from 'node:url'

export const UPSTREAM_WELCOME_NOTICE_VERSION = '2026-08-13.1'
const SETTINGS_NAMESPACE = 'ui-onboarding'
const ACKNOWLEDGEMENT_FIELD = 'welcomeNoticeVersion'

const [origin, modulesDirectory] = process.argv.slice(2)
if (origin === undefined || modulesDirectory === undefined) {
  throw new Error('usage: acknowledge-onboarding.mjs ORIGIN NODE_MODULES')
}

const clientUrl = pathToFileURL(join(
  modulesDirectory,
  '@deepseek-ai',
  'dsh-host-apiproxy',
  'lib',
  'types',
  'fetch',
  'client.js',
)).href
const { AbstractApiClient } = await import(clientUrl)

class LoopbackApiClient extends AbstractApiClient {
  resolveBase() {
    return origin
  }

  doFetch(input, init) {
    return fetch(input, init)
  }
}

function versionFrom(view) {
  const value = view?.value
  if (typeof value !== 'object' || value === null) return undefined
  const version = value[ACKNOWLEDGEMENT_FIELD]
  return typeof version === 'string' ? version : undefined
}

const client = new LoopbackApiClient(10_000)
const described = await client.settings.describe({})
if (!described.result.ok) {
  throw new Error(`Unable to read Harness onboarding settings: ${described.result.error.message}`)
}
const view = described.result.value.namespaces.find(candidate => candidate.ns === SETTINGS_NAMESPACE)
if (view === undefined) throw new Error('Harness onboarding settings are unavailable')

if (versionFrom(view) !== UPSTREAM_WELCOME_NOTICE_VERSION) {
  const mutated = await client.settings.mutate({
    ns: SETTINGS_NAMESPACE,
    ops: [{
      op: 'set',
      path: [ACKNOWLEDGEMENT_FIELD],
      value: UPSTREAM_WELCOME_NOTICE_VERSION,
    }],
  })
  if (!mutated.result.ok) {
    throw new Error(`Unable to update Harness onboarding settings: ${mutated.result.error.message}`)
  }
  if (versionFrom(mutated.result.value) !== UPSTREAM_WELCOME_NOTICE_VERSION) {
    throw new Error('Harness did not retain the welcome notice acknowledgement')
  }
}
