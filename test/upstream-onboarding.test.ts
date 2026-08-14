import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { createRequire } from 'node:module'
import { dirname, join } from 'node:path'
import test from 'node:test'
import {
  acknowledgeUpstreamWelcomeNotice,
  UPSTREAM_WELCOME_NOTICE_VERSION,
} from '../src/upstream-onboarding.js'

class MemoryGateway {
  writes: string[] = []

  constructor(private version: string | undefined) {}

  async readVersion(): Promise<string | undefined> {
    return this.version
  }

  async writeVersion(version: string): Promise<void> {
    this.version = version
    this.writes.push(version)
  }
}

test('acknowledges the current upstream welcome notice once', async () => {
  const gateway = new MemoryGateway(undefined)

  assert.equal(await acknowledgeUpstreamWelcomeNotice(gateway), true)
  assert.deepEqual(gateway.writes, [UPSTREAM_WELCOME_NOTICE_VERSION])
  assert.equal(await acknowledgeUpstreamWelcomeNotice(gateway), false)
  assert.deepEqual(gateway.writes, [UPSTREAM_WELCOME_NOTICE_VERSION])
})

test('replaces an acknowledgement for an older upstream notice', async () => {
  const gateway = new MemoryGateway('older-notice')

  assert.equal(await acknowledgeUpstreamWelcomeNotice(gateway), true)
  assert.deepEqual(gateway.writes, [UPSTREAM_WELCOME_NOTICE_VERSION])
})

test('pins the acknowledgement to the bundled upstream declaration', async () => {
  const require = createRequire(import.meta.url)
  const manifest = require.resolve('@deepseek-ai/dsh-client-ui-settings-models/package.json')
  const declaration = await readFile(join(dirname(manifest), 'lib', 'types', 'onboarding-copy.d.ts'), 'utf8')
  const match = /WELCOME_NOTICE_VERSION = "([^"]+)"/.exec(declaration)

  assert.equal(match?.[1], UPSTREAM_WELCOME_NOTICE_VERSION)

  const tauriHelper = await readFile(
    join(process.cwd(), 'src-tauri', 'scripts', 'acknowledge-onboarding.mjs'),
    'utf8',
  )
  const tauriMatch = /UPSTREAM_WELCOME_NOTICE_VERSION = '([^']+)'/.exec(tauriHelper)
  assert.equal(tauriMatch?.[1], UPSTREAM_WELCOME_NOTICE_VERSION)
})
