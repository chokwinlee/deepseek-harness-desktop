import { connectLoopback, callRemote, type LoopbackConnection } from 'dsh-desktop-settings-plugin/rpc'

const SETTINGS_NAMESPACE = 'ui-onboarding'
const ACKNOWLEDGEMENT_FIELD = 'welcomeNoticeVersion'

/** Welcome notice shipped by the pinned DeepSeek Harness release. */
export const UPSTREAM_WELCOME_NOTICE_VERSION = '2026-08-13.1'

interface WelcomeNoticeGateway {
  readVersion(): Promise<string | undefined>
  writeVersion(version: string): Promise<void>
}

function versionFrom(view: { value: unknown } | undefined): string | undefined {
  if (typeof view?.value !== 'object' || view.value === null) return undefined
  const version = (view.value as Record<string, unknown>)[ACKNOWLEDGEMENT_FIELD]
  return typeof version === 'string' ? version : undefined
}

class HarnessWelcomeNoticeGateway implements WelcomeNoticeGateway {
  constructor(private readonly connection: LoopbackConnection) {}

  async readVersion(): Promise<string | undefined> {
    const response = await callRemote<{ namespaces: Array<{ ns: string; value: unknown }> }>(this.connection, 'settings/describe', {})
    const view = response.namespaces.find(candidate => candidate.ns === SETTINGS_NAMESPACE)
    if (view === undefined) throw new Error('Harness onboarding settings are unavailable')
    return versionFrom(view)
  }

  async writeVersion(version: string): Promise<void> {
    const response = await callRemote<{ value: unknown }>(this.connection, 'settings/mutate', {
      ns: SETTINGS_NAMESPACE,
      ops: [{ op: 'set', path: [ACKNOWLEDGEMENT_FIELD], value: version }],
    })
    if (versionFrom(response) !== version) {
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
  const connection = await connectLoopback(origin)
  await acknowledgeUpstreamWelcomeNotice(new HarnessWelcomeNoticeGateway(connection))
}
