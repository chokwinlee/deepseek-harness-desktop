import assert from 'node:assert/strict'
import { fileURLToPath } from 'node:url'
import test from 'node:test'
import { HarnessSupervisor, parseHarnessUrl } from '../src/harness-supervisor.js'

const fixture = fileURLToPath(new URL('../../test/fixtures/fake-dsh.mjs', import.meta.url))

function supervisor(mode: string, startupTimeoutMs = 2_000): HarnessSupervisor {
  return new HarnessSupervisor({
    executable: process.execPath,
    script: fixture,
    cwd: process.cwd(),
    env: { ...process.env, FAKE_DSH_MODE: mode },
    startupTimeoutMs,
    // Windows can report a child exit tens of milliseconds after the process
    // has already terminated, so keep this below production's 300 ms grace
    // while leaving enough room for the platform event to arrive.
    readinessGraceMs: 200,
  })
}

test('accepts only an official loopback readiness URL', () => {
  assert.equal(parseHarnessUrl('dsh web: http://127.0.0.1:3080'), 'http://127.0.0.1:3080')
  assert.equal(parseHarnessUrl('dsh web: http://127.0.0.1:3080 (LAN: http://10.0.0.2:3080)'), 'http://127.0.0.1:3080')
  assert.equal(parseHarnessUrl('dsh web: http://localhost:3080'), undefined)
  assert.equal(parseHarnessUrl('dsh web: http://127.0.0.1:0'), undefined)
  assert.equal(parseHarnessUrl('dsh web: http://127.0.0.1:70000'), undefined)
})

test('resolves on readiness and stops the child', async () => {
  const runtime = supervisor('ready')
  await assert.doesNotReject(async () => {
    assert.equal(await runtime.start(), 'http://127.0.0.1:43123')
  })
  await assert.doesNotReject(runtime.stop())
})

test('reports an early process exit with recent output', async () => {
  const runtime = supervisor('exit')
  await assert.rejects(runtime.start(), /fixture startup failed/)
  await assert.doesNotReject(runtime.stop())
})

test('rejects a process that crashes immediately after readiness', async () => {
  const runtime = supervisor('unstable')
  await assert.rejects(runtime.start(), /fixture crashed after readiness/)
  await assert.doesNotReject(runtime.stop())
})

test('times out and can still terminate the child', async () => {
  const runtime = supervisor('silent', 50)
  await assert.rejects(runtime.start(), /did not become ready within 50 ms/)
  await assert.doesNotReject(runtime.stop())
})
