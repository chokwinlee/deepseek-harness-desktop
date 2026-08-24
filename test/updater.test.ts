import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { join } from 'node:path'
import test from 'node:test'
import { runInNewContext } from 'node:vm'

interface UpdaterTestApi {
  copyFor(locale: string): Record<string, string>
  findSettingsTriggerFrom(candidates: unknown[], excluded?: unknown): unknown | null
  harnessVersionLabel(raw: string): string
  isSettingsTriggerCandidate(candidate: unknown): boolean
  isNewer(latest: string, current: string): boolean
  localizedReleaseSummary(body: string, locale: string, fallback?: string): string
  markedReleaseSummary(body: string, locale: string): string
  parseVersion(raw: string): number[] | null
  resolveLocaleFromHints(hints: string[], languages: string[]): string
  runtimeSummary(desktop?: string, harness?: string): string
  shouldShowForStatus(status: string): boolean
  statusForRelease(tag: string, current: string, ignored: string | null): string
  summarize(body: string, fallback?: string): string
  versionLabel(raw: string): string
}

interface FakeDialogButtonOptions {
  titlebar?: boolean
  settingsArea?: boolean
}

function fakeDialogButton({ titlebar = false, settingsArea = false }: FakeDialogButtonOptions = {}) {
  return {
    getAttribute(name: string) {
      return name === 'aria-haspopup' ? 'dialog' : null
    },
    hasAttribute(name: string) {
      return name === 'aria-expanded'
    },
    closest(selector: string) {
      if (selector.includes('.dsh-usage-meter') && titlebar) return { className: 'dsh-usage-meter' }
      if (selector.includes('_settingsArea') && settingsArea) return { className: 'hash_settingsArea' }
      return null
    },
  }
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

test('never treats title-bar dialogs as the sidebar Settings trigger', async () => {
  const { api } = await loadUpdater()
  const usageSummary = fakeDialogButton({ titlebar: true })
  const sidebarSettings = fakeDialogButton({ settingsArea: true })

  assert.equal(api.isSettingsTriggerCandidate(usageSummary), false)
  assert.equal(api.findSettingsTriggerFrom([usageSummary]), null)
  assert.equal(api.findSettingsTriggerFrom([usageSummary, sidebarSettings]), sidebarSettings)
  assert.equal(api.findSettingsTriggerFrom([sidebarSettings], sidebarSettings), null)
})

test('hides the updater instead of mounting beside an unrelated dialog control', async () => {
  const { api } = await loadUpdater()
  const unrelatedDialog = fakeDialogButton()

  assert.equal(api.isSettingsTriggerCandidate(unrelatedDialog), false)
  assert.equal(api.findSettingsTriggerFrom([unrelatedDialog]), null)
})

test('labels the bundled Harness release separately from the Desktop version', async () => {
  const { api } = await loadUpdater()

  assert.equal(api.harnessVersionLabel('0.1.0-rc.8'), 'rc.8')
  assert.equal(api.harnessVersionLabel('0.2.0'), '0.2.0')
  assert.equal(api.runtimeSummary('0.2.1', '0.1.0-rc.8'), 'DSH Desktop v0.2.1 · Harness rc.8')
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

test('selects a concise localized release summary', async () => {
  const { api } = await loadUpdater()
  const body = `
<!-- dsh-summary:zh -->
## 中文
- 支持图片输入。
- 增加用量统计。
- 支持按需安装子代理。
<!-- /dsh-summary:zh -->

<!-- dsh-summary:en -->
## English
- Add image input.
- Add usage insights.
- Install subagents on demand.
<!-- /dsh-summary:en -->

## What's Changed
- Internal detail that should stay out of the update panel.
`

  assert.equal(api.markedReleaseSummary(body, 'zh').includes('支持图片输入'), true)
  assert.equal(
    api.localizedReleaseSummary(body, 'zh'),
    '• 支持图片输入。\n• 增加用量统计。\n• 支持按需安装子代理。',
  )
  assert.equal(
    api.localizedReleaseSummary(body, 'en'),
    '• Add image input.\n• Add usage insights.\n• Install subagents on demand.',
  )
  assert.equal(
    api.localizedReleaseSummary('- One\n- Two\n- Three\n- Four', 'en'),
    '• One\n• Two\n• Three',
  )
  assert.match(api.localizedReleaseSummary('x'.repeat(500), 'en'), /…$/)
})

test('keeps the updater inside the sidebar design and accessibility contract', async () => {
  const { source } = await loadUpdater()

  assert.match(source, /insertBefore\(host, nextTrigger\)/)
  assert.match(source, /__DSH_HARNESS_VERSION__/)
  assert.match(source, /window\.__DSH_DESKTOP_RUNTIME__ = runtimeStatus/)
  assert.match(source, /new CustomEvent\('dsh-desktop-runtime'/)
  assert.match(source, /var\(--dsw-alias-bg-layer-2/)
  assert.match(source, /aria-haspopup=\\?"dialog\\?"/)
  assert.match(source, /aria-expanded=\\?"false\\?"/)
  assert.match(source, /prefers-reduced-motion: reduce/)
  assert.match(source, /:host\(\[data-layout="rail"\]\)/)
  assert.match(source, /function positionRailHost\(\)/)
  assert.match(source, /TITLEBAR_SURFACE_SELECTOR/)
  assert.match(source, /SIDEBAR_SETTINGS_SURFACE_SELECTOR/)
  assert.doesNotMatch(source, /z-index:\s*2147483000/)
  assert.doesNotMatch(source, /position:\s*fixed;[\s\S]{0,80}left:\s*14px;[\s\S]{0,80}bottom:\s*14px;/)
})
