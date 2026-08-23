import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { join } from 'node:path'
import { runInNewContext } from 'node:vm'
import test from 'node:test'

interface SmoothStreamTestApi {
  isAppendChange: (previous: unknown, next: unknown) => boolean
  languageFromTag: (tag: string) => 'zh' | 'en'
  normalizeEnabled: (value: unknown, fallback?: boolean) => boolean
  revealBatchSize: (backlog: number) => number
  settingActionUrl: (enabled: boolean, token?: string) => string
  settingCopy: (language: 'zh' | 'en') => Record<string, string>
  splitGraphemes: (value: string) => string[]
}

async function loadTestApi(): Promise<SmoothStreamTestApi> {
  const source = await readFile(join(process.cwd(), 'src', 'smooth-stream.js'), 'utf8')
  const context: Record<string, unknown> = {
    URLSearchParams,
    __DSH_SMOOTH_STREAM_TEST__: true,
  }
  runInNewContext(source, context)
  return context.__DSH_SMOOTH_STREAM_TEST_API__ as SmoothStreamTestApi
}

test('smooth streaming is default-on and accepts explicit native values', async () => {
  const api = await loadTestApi()
  assert.equal(api.normalizeEnabled(undefined), true)
  assert.equal(api.normalizeEnabled('true'), true)
  assert.equal(api.normalizeEnabled('1'), true)
  assert.equal(api.normalizeEnabled('false'), false)
  assert.equal(api.normalizeEnabled('0'), false)
  assert.equal(api.normalizeEnabled('invalid', false), false)
})

test('smooth streaming setting uses the tokenized Desktop action protocol', async () => {
  const api = await loadTestApi()
  assert.equal(
    api.settingActionUrl(false, 'desktop-token'),
    'dsh-desktop://action/set-smooth-stream?token=desktop-token&enabled=0',
  )
  assert.equal(
    api.settingActionUrl(true, 'desktop-token'),
    'dsh-desktop://action/set-smooth-stream?token=desktop-token&enabled=1',
  )
})

test('smooth streaming setting copy follows the active DSH language', async () => {
  const api = await loadTestApi()
  assert.equal(api.languageFromTag('zh-CN'), 'zh')
  assert.equal(api.languageFromTag('en-US'), 'en')
  assert.equal(api.settingCopy('zh').title, '平滑流式输出')
  assert.equal(api.settingCopy('en').title, 'Smooth streaming')
})

test('smooth streaming settings observer does not self-trigger a frame loop', async () => {
  const source = await readFile(join(process.cwd(), 'src', 'smooth-stream.js'), 'utf8')
  assert.match(source, /settingText\.textContent !== copy\.title/)
  assert.match(source, /settingDescription\.textContent !== description/)
  assert.match(source, /settingRow\.parentElement !== slot\)\) scheduleMount\(\)/)
  assert.doesNotMatch(source, /\n    scheduleMount\(\)\n  }\n\n  function scheduleMount/)
})

test('smooth streaming recognizes append-only assistant text and reveals it adaptively', async () => {
  const api = await loadTestApi()
  assert.equal(api.isAppendChange('雨后', '雨后的城市'), true)
  assert.equal(api.isAppendChange('雨后', '城市雨后'), false)
  assert.equal(api.isAppendChange('雨后', '雨'), false)
  assert.deepEqual(Array.from(api.splitGraphemes('A👨‍👩‍👧‍👦中')), ['A', '👨‍👩‍👧‍👦', '中'])
  assert.equal(api.revealBatchSize(0), 0)
  assert.equal(api.revealBatchSize(1), 1)
  assert.equal(api.revealBatchSize(10), 3)
  assert.equal(api.revealBatchSize(100), 14)
})
