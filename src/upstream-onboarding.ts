import { AbstractApiClient, type IApiClient } from '@deepseek-ai/dsh-host-apiproxy/client'

const SETTINGS_NAMESPACE = 'ui-onboarding'
const ACKNOWLEDGEMENT_FIELD = 'welcomeNoticeVersion'

/** Welcome notice shipped by the pinned DeepSeek Harness release. */
export const UPSTREAM_WELCOME_NOTICE_VERSION = '2026-08-13.1'

interface WelcomeNoticeGateway {
  readVersion(): Promise<string | undefined>
  writeVersion(version: string): Promise<void>
}

class LoopbackApiClient extends AbstractApiClient {
  constructor(private readonly origin: string) {
    super(10_000)
  }

  protected override resolveBase(): string {
    return this.origin
  }

  protected override doFetch(input: URL, init?: RequestInit): Promise<Response> {
    return fetch(input, init)
  }
}

function versionFrom(view: { value: unknown } | undefined): string | undefined {
  if (typeof view?.value !== 'object' || view.value === null) return undefined
  const version = (view.value as Record<string, unknown>)[ACKNOWLEDGEMENT_FIELD]
  return typeof version === 'string' ? version : undefined
}

class HarnessWelcomeNoticeGateway implements WelcomeNoticeGateway {
  constructor(private readonly settings: IApiClient['settings']) {}

  async readVersion(): Promise<string | undefined> {
    const response = await this.settings.describe({})
    if (!response.result.ok) {
      throw new Error(`Unable to read Harness onboarding settings: ${response.result.error.message}`)
    }
    const view = response.result.value.namespaces.find(candidate => candidate.ns === SETTINGS_NAMESPACE)
    if (view === undefined) throw new Error('Harness onboarding settings are unavailable')
    return versionFrom(view)
  }

  async writeVersion(version: string): Promise<void> {
    const response = await this.settings.mutate({
      ns: SETTINGS_NAMESPACE,
      ops: [{ op: 'set', path: [ACKNOWLEDGEMENT_FIELD], value: version }],
    })
    if (!response.result.ok) {
      throw new Error(`Unable to update Harness onboarding settings: ${response.result.error.message}`)
    }
    if (versionFrom(response.result.value) !== version) {
      throw new Error('Harness did not retain the welcome notice acknowledgement')
    }
  }
}

/** Record the pinned upstream notice as acknowledged before the Web UI loads. */
export async function acknowledgeUpstreamWelcomeNotice(gateway: WelcomeNoticeGateway): Promise<boolean> {
  if (await gateway.readVersion() === UPSTREAM_WELCOME_NOTICE_VERSION) return false
  await gateway.writeVersion(UPSTREAM_WELCOME_NOTICE_VERSION)
  return true
}

/** Suppress the non-functional upstream welcome notice through its settings API. */
export async function suppressUpstreamWelcomeNotice(origin: string): Promise<void> {
  const client = new LoopbackApiClient(origin)
  await acknowledgeUpstreamWelcomeNotice(new HarnessWelcomeNoticeGateway(client.settings))
}
