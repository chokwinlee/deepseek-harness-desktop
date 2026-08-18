import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { join } from 'node:path'
import test from 'node:test'
import { runInNewContext } from 'node:vm'

interface UsageMeterTestApi {
  costForRecord(record: unknown, index: unknown): { cost: number; priced: boolean; source: string | null }
  createOpenRouterIndex(models: unknown[]): unknown
  deepseekOfficialPrice(timestamp: number, provider: string, model: string): {
    prompt: number
    completion: number
    cacheRead: number
  } | null
  matchOpenRouterModel(index: unknown, provider: string, model: string): { id: string } | null
  sessionAverageTps(stats: unknown): number
  sumSessionTps(stats: unknown[]): number
}

interface UsageMeterSandbox {
  __DSH_USAGE_METER_TEST__: true
  __DSH_USAGE_METER_TEST_API__?: UsageMeterTestApi
}

async function loadUsageMeter() {
  const source = await readFile(join(process.cwd(), 'src', 'usage-meter.js'), 'utf8')
  const sandbox: UsageMeterSandbox = { __DSH_USAGE_METER_TEST__: true }
  runInNewContext(source, sandbox)
  assert.ok(sandbox.__DSH_USAGE_METER_TEST_API__)
  return { api: sandbox.__DSH_USAGE_METER_TEST_API__, source }
}

test('applies the time-versioned official DeepSeek V4 price before catalog fallback', async () => {
  const { api } = await loadUsageMeter()
  const before = api.deepseekOfficialPrice(
    Date.parse('2026-08-16T15:00:00Z'),
    'deepseek-official',
    'deepseek-v4-flash',
  )
  const peak = api.deepseekOfficialPrice(
    Date.parse('2026-08-17T02:00:00Z'),
    'deepseek-official',
    'deepseek-v4-flash',
  )

  assert.equal(before?.prompt, 0.14 / 1_000_000)
  assert.equal(before?.completion, 0.28 / 1_000_000)
  assert.equal(peak?.prompt, 0.44 / 1_000_000)
  assert.equal(peak?.cacheRead, 0.014 / 1_000_000)
  assert.equal(peak?.completion, 1.32 / 1_000_000)
})

test('matches major providers against exact OpenRouter model ids and prices cache buckets', async () => {
  const { api } = await loadUsageMeter()
  const index = api.createOpenRouterIndex([
    {
      id: 'openai/gpt-5.6-sol',
      pricing: {
        prompt: '0.000001',
        completion: '0.000004',
        input_cache_read: '0.0000002',
        input_cache_write: '0.00000125',
        request: '0',
      },
    },
    {
      id: 'anthropic/claude-sonnet-5',
      pricing: { prompt: '0.000003', completion: '0.000015' },
    },
  ])

  assert.equal(api.matchOpenRouterModel(index, 'openai', 'gpt-5.6-sol')?.id, 'openai/gpt-5.6-sol')
  assert.equal(
    api.matchOpenRouterModel(index, 'anthropic', 'claude-sonnet-5')?.id,
    'anthropic/claude-sonnet-5',
  )
  const priced = api.costForRecord({
    time: Date.now(),
    provider: 'openai',
    model: 'gpt-5.6-sol',
    usage: {
      inputTokens: 1_000,
      outputTokens: 100,
      cacheReadTokens: 2_000,
      cacheWriteTokens: 500,
    },
  }, index)
  assert.equal(priced.priced, true)
  assert.equal(priced.source, 'OpenRouter')
  assert.equal(priced.cost, 0.002425)
})

test('keeps unmatched models unpriced and sums authoritative running-session throughput', async () => {
  const { api, source } = await loadUsageMeter()
  const index = api.createOpenRouterIndex([])
  const result = api.costForRecord({
    time: Date.now(),
    provider: 'custom-gateway',
    model: 'private-model',
    usage: { inputTokens: 100, outputTokens: 20 },
  }, index)

  assert.equal(result.priced, false)
  assert.equal(api.sessionAverageTps({ decodeTokens: 25_093, decodeMs: 224_725 }), 25_093 / 224.725)
  assert.equal(Math.round(api.sessionAverageTps({ decodeTokens: 25_093, decodeMs: 224_725 })), 112)
  assert.equal(api.sessionAverageTps({ decodeTokens: 100, decodeMs: 0 }), 0)
  assert.equal(api.sumSessionTps([
    { decodeTokens: 25_093, decodeMs: 224_725 },
    { decodeTokens: 1_120, decodeMs: 10_000 },
    undefined,
  ]), (25_093 / 224.725) + 112)
  assert.match(source, /部分未定价/)
  assert.match(source, />\$\{roundedTps\} tok\/s<\/span>/)
  assert.doesNotMatch(source, /≈\$\{roundedTps\}/)
  assert.match(source, /projections\?\.values\?\.sessionStats/)
  assert.match(source, /frame\.key === 'sessionStats'/)
  assert.doesNotMatch(source, /estimateTokens|TPS_WINDOW_MS|tokenSamples/)
  assert.doesNotMatch(source, /价格来源/)
  assert.match(source, /class="dsh-usage-live-rate"/)
  assert.doesNotMatch(source, /flex: 0 0 10ch/)
  assert.match(source, /data-digits="\$\{rateDigits\}"/)
  assert.match(source, /data-digits="1"\]::after \{ width: 2ch/)
  assert.match(source, /data-digits="2"\]::after \{ width: 1ch/)
  assert.match(source, /width: 348px/)
  assert.doesNotMatch(source, /width: 400px/)
  assert.match(source, /dsh-usage-period:last-of-type \{ border-bottom: 0/)
  assert.doesNotMatch(source, /最近 5 秒滚动估算/)
  assert.doesNotMatch(source, /未匹配模型不会按 0 元计算/)
  assert.doesNotMatch(source, /backdrop-filter/)
})

test('keeps the title-bar background draggable without swallowing usage controls', async () => {
  const { source } = await loadUsageMeter()
  const capability = JSON.parse(await readFile(
    join(process.cwd(), 'src-tauri', 'capabilities', 'main-window-drag.json'),
    'utf8',
  ))

  assert.match(source, /host\.setAttribute\('data-tauri-drag-region', ''\)/)
  assert.match(source, /\.dsh-usage-meter \{[^}]*-webkit-app-region: drag;[^}]*pointer-events: auto;/)
  assert.match(source, /\.dsh-usage-summary \{[^}]*-webkit-app-region: no-drag;[^}]*pointer-events: auto;/)
  assert.match(source, /\.dsh-usage-popover \{[^}]*-webkit-app-region: no-drag;[^}]*pointer-events: none;/)
  assert.doesNotMatch(source, /\.dsh-usage-meter \{[^}]*-webkit-app-region: no-drag;/)
  assert.deepEqual(capability.windows, ['main'])
  assert.deepEqual(capability.remote.urls, ['http://127.0.0.1:*'])
  assert.deepEqual(capability.permissions, ['core:window:allow-start-dragging'])
})
