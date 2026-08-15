import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { join } from 'node:path'
import test from 'node:test'
import { runInNewContext } from 'node:vm'

interface UpdaterTestApi {
  copyFor(locale: string): Record<string, string>
  isNewer(latest: string, current: string): boolean
  parseVersion(raw: string): number[] | null
  resolveLocaleFromHints(hints: string[], languages: string[]): string
  shouldShowForStatus(status: string): boolean
  statusForRelease(tag: string, current: string, ignored: string | null): string
  summarize(body: string, fallback?: string): string
  versionLabel(raw: string): string
}

interface UpdaterSandbox {
  __DSH_UPDATER_TEST__: true
  __DSH_UPDATER_TEST_API__?: UpdaterTestApi
}

async function loadUpdater(): Promise<{ api: UpdaterTestApi; source: string }> {
  const source = await readFile(join(process.cwd(), 'src', 'updater.js'), 'utf8')
  const sandbox: UpdaterSandbox = { __DSH_UPDATER_TEST__: true }
  runInNewContext(source, sandbox)
  assert.ok(sandbox.__DSH_UPDATER_TEST_API__)
  return { api: sandbox.__DSH_UPDATER_TEST_API__, source }
}

test('compares release versions and classifies ignored updates', async () => {
  const { api } = await loadUpdater()

  assert.deepEqual(Array.from(api.parseVersion('v1.2.3') ?? []), [1, 2, 3])
  assert.equal(api.versionLabel('1.2.3-beta.1'), 'v1.2.3')
  assert.equal(api.isNewer('v1.3.0', 'v1.2.9'), true)
  assert.equal(api.isNewer('v1.2.3', 'v1.2.3'), false)
  assert.equal(api.statusForRelease('v1.3.0', 'v1.2.9', null), 'update')
  assert.equal(api.statusForRelease('v1.3.0', 'v1.2.9', 'v1.3.0'), 'ignored')
  assert.equal(api.statusForRelease('v1.2.9', 'v1.2.9', null), 'current')
  assert.equal(api.statusForRelease('v1.2.9', 'v1.2.9', 'v1.2.9'), 'current')
})

test('follows the visible Harness locale before the browser fallback', async () => {
  const { api } = await loadUpdater()

  assert.equal(api.resolveLocaleFromHints(['Settings'], ['zh-CN']), 'en')
  assert.equal(api.resolveLocaleFromHints(['设置'], ['en-US']), 'zh')
  assert.equal(api.resolveLocaleFromHints([], ['en-GB']), 'en')
  assert.equal(api.copyFor('en').updateTitle, 'Update available')
  assert.equal(api.copyFor('zh').updateTitle, '发现新版本')
})

test('shows the desktop control only for an available update', async () => {
  const { api } = await loadUpdater()

  assert.equal(api.shouldShowForStatus('update'), true)
  assert.equal(api.shouldShowForStatus('checking'), false)
  assert.equal(api.shouldShowForStatus('current'), false)
  assert.equal(api.shouldShowForStatus('error'), false)
  assert.equal(api.shouldShowForStatus('ignored'), false)
})

test('normalizes release notes without exposing markdown chrome', async () => {
  const { api } = await loadUpdater()

  assert.equal(
    api.summarize('## Changes\n\n**Fixed** [update UI](https://example.com).'),
    'Changes\n\nFixed update UI.',
  )
  assert.equal(api.summarize('', 'No release notes.'), 'No release notes.')
  assert.match(api.summarize('x'.repeat(500)), /…$/)
})

test('keeps the updater inside the sidebar design and accessibility contract', async () => {
  const { source } = await loadUpdater()

  assert.match(source, /insertBefore\(host, nextTrigger\)/)
  assert.match(source, /var\(--dsw-alias-bg-layer-2/)
  assert.match(source, /aria-haspopup=\\?"dialog\\?"/)
  assert.match(source, /aria-expanded=\\?"false\\?"/)
  assert.match(source, /prefers-reduced-motion: reduce/)
  assert.match(source, /:host\(\[data-layout="rail"\]\)/)
  assert.match(source, /function positionRailHost\(\)/)
  assert.doesNotMatch(source, /z-index:\s*2147483000/)
  assert.doesNotMatch(source, /position:\s*fixed;[\s\S]{0,80}left:\s*14px;[\s\S]{0,80}bottom:\s*14px;/)
})
