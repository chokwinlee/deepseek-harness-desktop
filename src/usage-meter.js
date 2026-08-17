/**
 * Desktop title-bar usage meter.
 *
 * Durable usage is extracted by the native shell from local DSH session logs;
 * this client only receives timestamp/provider/model/token buckets. Running TPS
 * uses DSH's authoritative sessionStats projection, summed across active sessions.
 */
(() => {
  'use strict'

  const ACTION_TOKEN = '__DSH_ACTION_TOKEN__'
  const SNAPSHOT_ACTION = 'usage-snapshot'
  const OPENROUTER_MODELS_URL = 'https://openrouter.ai/api/v1/models?output_modalities=text'
  const DAY_MS = 86_400_000
  const DEEPSEEK_V4_PRICE_CHANGE = Date.parse('2026-08-16T16:00:00Z')

  const copy = {
    zh: {
      today: '今日',
      sevenDays: '近 7 天',
      tasks: '个任务',
      estimated: '估',
      unpriced: '未定价',
      partiallyPriced: '部分未定价',
      loading: '正在统计用量…',
      input: '未缓存输入',
      cacheRead: '缓存命中',
      cacheWrite: '缓存写入',
      output: '输出',
      tokens: 'Token',
      cost: '估算费用',
      live: '运行任务总均速',
      running: '运行中',
      noUsage: '暂无用量',
      scanWarning: '部分旧会话未能读取',
    },
    en: {
      today: 'Today',
      sevenDays: '7 days',
      tasks: 'tasks',
      estimated: 'est.',
      unpriced: 'Unpriced',
      partiallyPriced: 'Partially unpriced',
      loading: 'Calculating usage…',
      input: 'Uncached input',
      cacheRead: 'Cache read',
      cacheWrite: 'Cache write',
      output: 'Output',
      tokens: 'Tokens',
      cost: 'Estimated cost',
      live: 'Running tasks avg.',
      running: 'Running',
      noUsage: 'No usage yet',
      scanWarning: 'Some older sessions could not be read',
    },
  }

  function locale() {
    const hints = [document?.documentElement?.lang, ...(navigator?.languages || [])]
    return hints.some(value => String(value || '').toLowerCase().startsWith('zh')) ? 'zh' : 'en'
  }

  function localDayKey(timestamp) {
    const date = new Date(timestamp)
    const year = date.getFullYear()
    const month = String(date.getMonth() + 1).padStart(2, '0')
    const day = String(date.getDate()).padStart(2, '0')
    return `${year}-${month}-${day}`
  }

  function startOfLocalDay(timestamp = Date.now(), daysAgo = 0) {
    const date = new Date(timestamp)
    return new Date(date.getFullYear(), date.getMonth(), date.getDate() - daysAgo).getTime()
  }

  function lastSevenDayKeys(now = Date.now()) {
    return Array.from({ length: 7 }, (_, index) => localDayKey(startOfLocalDay(now, index)))
  }

  function number(value) {
    const parsed = Number(value)
    return Number.isFinite(parsed) && parsed > 0 ? parsed : 0
  }

  function usageOf(record) {
    const usage = record?.usage || {}
    return {
      inputTokens: number(usage.inputTokens),
      outputTokens: number(usage.outputTokens),
      cacheReadTokens: number(usage.cacheReadTokens),
      cacheWriteTokens: number(usage.cacheWriteTokens),
    }
  }

  function totalTokens(usage) {
    return usage.inputTokens + usage.outputTokens + usage.cacheReadTokens + usage.cacheWriteTokens
  }

  function deepseekOfficialPrice(timestamp, provider, model) {
    if (!['deepseek-official', 'deepseek'].includes(String(provider || '').toLowerCase())) return null
    const id = String(model || '').toLowerCase()
    if (id !== 'deepseek-v4-flash' && id !== 'deepseek-v4-pro') return null

    let cacheReadPerMillion
    let inputPerMillion
    let outputPerMillion
    if (timestamp < DEEPSEEK_V4_PRICE_CHANGE) {
      if (id === 'deepseek-v4-flash') {
        cacheReadPerMillion = 0.0028
        inputPerMillion = 0.14
        outputPerMillion = 0.28
      } else {
        cacheReadPerMillion = 0.003625
        inputPerMillion = 0.435
        outputPerMillion = 0.87
      }
    } else {
      const hour = new Date(timestamp).getUTCHours()
      const peak = (hour >= 1 && hour < 4) || (hour >= 6 && hour < 10)
      if (id === 'deepseek-v4-flash') {
        cacheReadPerMillion = peak ? 0.014 : 0.007
        inputPerMillion = peak ? 0.44 : 0.22
        outputPerMillion = peak ? 1.32 : 0.66
      } else {
        cacheReadPerMillion = peak ? 0.044 : 0.022
        inputPerMillion = peak ? 1.32 : 0.66
        outputPerMillion = peak ? 3.96 : 1.98
      }
    }
    return {
      prompt: inputPerMillion / 1_000_000,
      completion: outputPerMillion / 1_000_000,
      cacheRead: cacheReadPerMillion / 1_000_000,
      cacheWrite: inputPerMillion / 1_000_000,
      request: 0,
      source: 'DeepSeek official',
      matchedModel: id,
    }
  }

  const providerAuthors = new Map([
    ['anthropic', 'anthropic'],
    ['azure-openai-responses', 'openai'],
    ['deepseek', 'deepseek'],
    ['deepseek-official', 'deepseek'],
    ['google', 'google'],
    ['google-vertex', 'google'],
    ['kimi-coding', 'moonshotai'],
    ['minimax', 'minimax'],
    ['minimax-cn', 'minimax'],
    ['mistral', 'mistralai'],
    ['moonshotai', 'moonshotai'],
    ['moonshotai-cn', 'moonshotai'],
    ['openai', 'openai'],
    ['qwen-token-plan', 'qwen'],
    ['qwen-token-plan-cn', 'qwen'],
    ['xai', 'x-ai'],
    ['zai', 'z-ai'],
    ['zai-coding-cn', 'z-ai'],
  ])

  function normalizeModelId(value) {
    return String(value || '')
      .trim()
      .toLowerCase()
      .replace(/^models\//, '')
      .replace(/^openrouter\//, '')
  }

  function createOpenRouterIndex(models) {
    const exact = new Map()
    const basenames = new Map()
    for (const model of Array.isArray(models) ? models : []) {
      const ids = [model?.id, model?.canonical_slug]
        .map(normalizeModelId)
        .filter(Boolean)
      for (const id of ids) {
        if (!exact.has(id)) exact.set(id, model)
        const basename = id.includes('/') ? id.slice(id.indexOf('/') + 1) : id
        const entries = basenames.get(basename) || []
        if (!entries.includes(model)) entries.push(model)
        basenames.set(basename, entries)
      }
    }
    return { exact, basenames }
  }

  function matchOpenRouterModel(index, provider, model) {
    if (!index) return null
    const normalized = normalizeModelId(model)
    if (!normalized) return null
    const candidates = [normalized]
    const author = providerAuthors.get(String(provider || '').toLowerCase())
    if (author && !normalized.includes('/')) candidates.unshift(`${author}/${normalized}`)
    for (const candidate of candidates) {
      const match = index.exact.get(candidate)
      if (match) return match
    }
    const basename = normalized.includes('/') ? normalized.slice(normalized.indexOf('/') + 1) : normalized
    const unique = index.basenames.get(basename) || []
    return unique.length === 1 ? unique[0] : null
  }

  function openRouterPrice(model, inputTokens) {
    if (!model) return null
    const raw = model.pricing
    const tiers = Array.isArray(raw) ? raw : raw ? [raw] : []
    if (tiers.length === 0) return null
    const sorted = [...tiers].sort((a, b) => number(a?.min_context) - number(b?.min_context))
    let selected = sorted[0]
    for (const tier of sorted) {
      if (number(tier?.min_context) <= inputTokens) selected = tier
    }
    const prompt = Number(selected?.prompt)
    const completion = Number(selected?.completion)
    if (!Number.isFinite(prompt) || !Number.isFinite(completion)) return null
    const cacheRead = Number(selected?.input_cache_read)
    const cacheWrite = Number(selected?.input_cache_write)
    const request = Number(selected?.request)
    return {
      prompt,
      completion,
      cacheRead: Number.isFinite(cacheRead) ? cacheRead : prompt,
      cacheWrite: Number.isFinite(cacheWrite) ? cacheWrite : prompt,
      request: Number.isFinite(request) ? request : 0,
      source: 'OpenRouter',
      matchedModel: model.id,
    }
  }

  function priceForRecord(record, openRouterIndex) {
    const usage = usageOf(record)
    const official = deepseekOfficialPrice(record.time, record.provider, record.model)
    if (official) return official
    const model = matchOpenRouterModel(openRouterIndex, record.provider, record.model)
    return openRouterPrice(model, usage.inputTokens + usage.cacheReadTokens + usage.cacheWriteTokens)
  }

  function costForRecord(record, openRouterIndex) {
    const usage = usageOf(record)
    const price = priceForRecord(record, openRouterIndex)
    if (!price) return { cost: 0, priced: false, source: null, matchedModel: null }
    const cost = usage.inputTokens * price.prompt
      + usage.outputTokens * price.completion
      + usage.cacheReadTokens * price.cacheRead
      + usage.cacheWriteTokens * price.cacheWrite
      + price.request
    return {
      cost: Number.isFinite(cost) ? cost : 0,
      priced: true,
      source: price.source,
      matchedModel: price.matchedModel,
    }
  }

  function sessionAverageTps(stats) {
    const decodeMs = number(stats?.decodeMs)
    if (decodeMs <= 0) return 0
    return number(stats?.decodeTokens) / (decodeMs / 1_000)
  }

  function sumSessionTps(stats) {
    return Array.from(stats || []).reduce((sum, value) => sum + sessionAverageTps(value), 0)
  }

  function formatTokens(value, language = 'zh') {
    const amount = number(value)
    if (amount >= 1_000_000) return `${(amount / 1_000_000).toFixed(amount >= 10_000_000 ? 1 : 2)}M`
    if (amount >= 1_000) return `${(amount / 1_000).toFixed(amount >= 100_000 ? 0 : 1)}K`
    return Math.round(amount).toLocaleString(language === 'zh' ? 'zh-CN' : 'en-US')
  }

  function emptyBucket() {
    return {
      inputTokens: 0,
      outputTokens: 0,
      cacheReadTokens: 0,
      cacheWriteTokens: 0,
      cost: 0,
      calls: 0,
      unpricedCalls: 0,
      sources: new Set(),
    }
  }

  function addRecord(bucket, record, openRouterIndex) {
    const usage = usageOf(record)
    bucket.inputTokens += usage.inputTokens
    bucket.outputTokens += usage.outputTokens
    bucket.cacheReadTokens += usage.cacheReadTokens
    bucket.cacheWriteTokens += usage.cacheWriteTokens
    bucket.calls += 1
    const pricing = costForRecord(record, openRouterIndex)
    if (pricing.priced) {
      bucket.cost += pricing.cost
      bucket.sources.add(pricing.source)
    } else {
      bucket.unpricedCalls += 1
    }
    return bucket
  }

  function mergeBuckets(buckets) {
    const merged = emptyBucket()
    for (const bucket of buckets) {
      merged.inputTokens += bucket.inputTokens
      merged.outputTokens += bucket.outputTokens
      merged.cacheReadTokens += bucket.cacheReadTokens
      merged.cacheWriteTokens += bucket.cacheWriteTokens
      merged.cost += bucket.cost
      merged.calls += bucket.calls
      merged.unpricedCalls += bucket.unpricedCalls
      for (const source of bucket.sources) merged.sources.add(source)
    }
    return merged
  }

  const testGlobal = typeof globalThis === 'undefined' ? null : globalThis
  if (testGlobal?.__DSH_USAGE_METER_TEST__ === true) {
    testGlobal.__DSH_USAGE_METER_TEST_API__ = Object.freeze({
      costForRecord,
      createOpenRouterIndex,
      deepseekOfficialPrice,
      formatTokens,
      lastSevenDayKeys,
      localDayKey,
      matchOpenRouterModel,
      openRouterPrice,
      sessionAverageTps,
      startOfLocalDay,
      sumSessionTps,
    })
    return
  }

  if (typeof window === 'undefined' || typeof document === 'undefined') return
  const trustedHarness = location.protocol === 'http:' && location.hostname === '127.0.0.1'
  const isMac = /Mac/i.test(navigator.platform || navigator.userAgent || '')
  if (!trustedHarness || !isMac) return

  const language = locale()
  const t = copy[language]
  const records = new Map()
  const runningSessions = new Set()
  const sessionStatsById = new Map()
  const activeSteps = new Map()
  let openRouterIndex = null
  let openRouterLoaded = false
  let snapshotLoaded = false
  let scanWarnings = 0
  let renderTimer = 0
  let host
  let summaryButton
  let popover
  let runningTps = 0

  function rpc(method, payload = {}) {
    const rpcId = crypto.randomUUID()
    return fetch(`/api/${method}`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ type: 'client-request', rpcId, method, payload }),
    }).then(async response => {
      if (!response.ok) throw new Error(`${method}: HTTP ${response.status}`)
      const body = await response.json()
      if (body?.rpcId !== rpcId || body?.result?.ok !== true) {
        throw new Error(body?.result?.error?.message || `${method}: invalid response`)
      }
      return body.result.value
    })
  }

  function requestSnapshot() {
    const query = new URLSearchParams({
      token: ACTION_TOKEN,
      cutoff: String(startOfLocalDay(Date.now(), 6)),
    })
    location.assign(`dsh-desktop://action/${SNAPSHOT_ACTION}?${query.toString()}`)
  }

  async function loadOpenRouterPricing() {
    try {
      const response = await fetch(OPENROUTER_MODELS_URL, { cache: 'force-cache', mode: 'cors' })
      if (!response.ok) throw new Error(`OpenRouter models: HTTP ${response.status}`)
      const body = await response.json()
      openRouterIndex = createOpenRouterIndex(body?.data)
    } catch (error) {
      console.warn('[dsh-usage] OpenRouter pricing unavailable:', error)
    } finally {
      openRouterLoaded = true
      scheduleRender()
    }
  }

  async function loadRunningSessions() {
    try {
      const value = await rpc('session.list')
      for (const item of value?.items || []) {
        if (item?.running) runningSessions.add(item.sessionId)
        const stats = item?.projections?.values?.sessionStats
        if (stats) sessionStatsById.set(item.sessionId, stats)
      }
    } catch (error) {
      console.warn('[dsh-usage] running-session baseline unavailable:', error)
    }
    scheduleRender()
  }

  function stepKey(event) {
    return `${event?.data?.turn ?? '?'}:${event?.data?.step ?? '?'}`
  }

  function recordAssistantMessage(sessionId, event) {
    const data = event?.data
    const usage = data?.usage
    const message = data?.message
    if (!usage || !message?.id) return
    records.set(message.id, {
      id: message.id,
      time: number(event.time) || Date.now(),
      provider: message?.source?.provider || '',
      model: message?.source?.model || '',
      usage,
    })
    scheduleRender()
  }

  function handleSessionEvent(sessionId, event) {
    if (!event) return
    if (event.type === 'step/start') {
      const key = `${sessionId}:${stepKey(event)}`
      if (!activeSteps.has(key)) {
        activeSteps.set(key, { sessionId, key: stepKey(event) })
      }
      runningSessions.add(sessionId)
    } else if (event.type === 'assistant/message') {
      recordAssistantMessage(sessionId, event)
    } else if (event.type === 'step/end') {
      activeSteps.delete(`${sessionId}:${stepKey(event)}`)
    } else if (event.type === 'turn/end') {
      runningSessions.delete(sessionId)
    }
    scheduleRender()
  }

  function openDownlink(path, handleFrame) {
    let stopped = false
    let retryMs = 500
    let socket
    const connect = () => {
      if (stopped) return
      const url = new URL(path, location.origin)
      url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:'
      socket = new WebSocket(url)
      socket.addEventListener('open', () => { retryMs = 500 })
      socket.addEventListener('message', message => {
        try {
          const envelope = JSON.parse(message.data)
          handleFrame(envelope?.payload)
        } catch (error) {
          console.warn(`[dsh-usage] dropped malformed ${path} frame:`, error)
        }
      })
      socket.addEventListener('close', () => {
        if (stopped) return
        window.setTimeout(connect, retryMs)
        retryMs = Math.min(retryMs * 2, 10_000)
      })
    }
    connect()
    return () => {
      stopped = true
      if (socket?.readyState === WebSocket.CONNECTING || socket?.readyState === WebSocket.OPEN) socket.close()
    }
  }

  function currentTps() {
    return sumSessionTps([...runningSessions].map(sessionId => sessionStatsById.get(sessionId)))
  }

  function aggregateUsage(now = Date.now()) {
    const buckets = new Map(lastSevenDayKeys(now).map(key => [key, emptyBucket()]))
    const cutoff = startOfLocalDay(now, 6)
    for (const record of records.values()) {
      if (record.time < cutoff) continue
      const bucket = buckets.get(localDayKey(record.time))
      if (bucket) addRecord(bucket, record, openRouterIndex)
    }
    const today = buckets.get(localDayKey(now)) || emptyBucket()
    const sevenDays = mergeBuckets([...buckets.values()])
    return { today, sevenDays }
  }

  function costLabel(bucket, compact = false) {
    if (bucket.calls === 0) return '$0.00'
    if (bucket.unpricedCalls === bucket.calls) return t.unpriced
    const precision = bucket.cost < 0.01 ? 4 : 2
    const label = `$${bucket.cost.toFixed(precision)}`
    if (bucket.unpricedCalls > 0) return `${label}+`
    return compact ? label : `${label} USD`
  }

  function detailRow(label, bucket) {
    const tokens = totalTokens(bucket)
    return `
      <section class="dsh-usage-period">
        <div class="dsh-usage-period-head">
          <span>${label}</span>
          <strong>${formatTokens(tokens, language)}</strong>
        </div>
        <div class="dsh-usage-cost">
          <span>${t.cost}</span>
          <strong>${costLabel(bucket)}</strong>
        </div>
        <dl class="dsh-usage-breakdown">
          <div><dt>${t.input}</dt><dd>${formatTokens(bucket.inputTokens, language)}</dd></div>
          <div><dt>${t.cacheRead}</dt><dd>${formatTokens(bucket.cacheReadTokens, language)}</dd></div>
          <div><dt>${t.cacheWrite}</dt><dd>${formatTokens(bucket.cacheWriteTokens, language)}</dd></div>
          <div><dt>${t.output}</dt><dd>${formatTokens(bucket.outputTokens, language)}</dd></div>
        </dl>
        ${bucket.unpricedCalls > 0 ? `<p class="dsh-usage-warning">${t.partiallyPriced} · ${bucket.unpricedCalls}/${bucket.calls}</p>` : ''}
      </section>`
  }

  function render() {
    renderTimer = 0
    if (!summaryButton || !popover) return
    runningTps = currentTps()
    const { today, sevenDays } = aggregateUsage()
    const ready = snapshotLoaded && openRouterLoaded
    const runningCount = new Set([
      ...runningSessions,
      ...[...activeSteps.values()].map(step => step.sessionId),
    ]).size

    if (!ready) {
      summaryButton.innerHTML = `<span class="dsh-usage-pulse"></span><span>${t.loading}</span>`
    } else {
      const todayTokens = totalTokens(today)
      const roundedTps = Math.round(runningTps)
      const rateDigits = Math.min(3, String(Math.abs(roundedTps)).length)
      summaryButton.innerHTML = `
        <span class="dsh-usage-today">${t.today} ${formatTokens(todayTokens, language)} · ${costLabel(today, true)} <small>${t.estimated}</small></span>
        <span class="dsh-usage-divider"></span>
        <span class="dsh-usage-live"><i class="${runningCount ? 'is-running' : ''}"></i><span>${runningCount} ${t.tasks} ·</span><span class="dsh-usage-live-rate" data-digits="${rateDigits}">${roundedTps} tok/s</span></span>`
    }

    popover.innerHTML = `
      <header class="dsh-usage-popover-head">
        <div><span>${t.live}</span><strong>${Math.round(runningTps)} <small>tok/s</small></strong></div>
        <div><span>${t.running}</span><strong>${runningCount} <small>${t.tasks}</small></strong></div>
      </header>
      ${ready ? detailRow(t.today, today) + detailRow(t.sevenDays, sevenDays) : `<p class="dsh-usage-empty">${t.loading}</p>`}
      ${scanWarnings ? `<p class="dsh-usage-scan-warning">${t.scanWarning} · ${scanWarnings}</p>` : ''}`
  }

  function scheduleRender() {
    if (renderTimer) return
    renderTimer = window.setTimeout(render, 0)
  }

  function installStyle() {
    const style = document.createElement('style')
    style.dataset.dshUsageMeter = 'true'
    style.textContent = `
      body.dsh-native-titlebar-overlay { box-sizing: border-box !important; padding-top: 32px !important; }
      .dsh-usage-meter { --meter-bg: #f6f7f9; --meter-layer: #fff; --meter-subtle: #f2f4f7; --meter-text: #22252b; --meter-muted: #66707c; --meter-border: rgba(20,26,35,.14); --meter-accent: #3b6ff5; position: fixed; z-index: 2147483646; top: 0; left: 0; right: 0; height: 32px; display: flex; justify-content: center; color: var(--dsw-alias-fg-default,var(--meter-text)); font-family: -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif; font-size: 11px; line-height: 1; text-rendering: optimizeLegibility; -webkit-app-region: no-drag; pointer-events: none; }
      body[data-ds-dark-theme] .dsh-usage-meter { --meter-bg: #24272d; --meter-layer: #202329; --meter-subtle: #292d34; --meter-text: #f1f3f6; --meter-muted: #aeb4bf; --meter-border: rgba(255,255,255,.14); --meter-accent: #7d9cff; }
      .dsh-usage-summary { box-sizing: border-box; max-width: calc(100vw - 96px); height: 22px; margin-top: 5px; padding: 0 10px; display: flex; align-items: center; gap: 8px; overflow: hidden; border: 1px solid var(--meter-border); border-radius: 8px; color: inherit; background: var(--meter-bg); box-shadow: 0 1px 0 rgba(255,255,255,.12) inset; cursor: default; white-space: nowrap; font: inherit; font-weight: 500; letter-spacing: .01em; pointer-events: auto; }
      .dsh-usage-summary:hover, .dsh-usage-summary[aria-expanded="true"] { border-color: color-mix(in srgb,var(--meter-accent) 42%,var(--meter-border)); background: var(--meter-layer); }
      .dsh-usage-summary:focus-visible { outline: 2px solid color-mix(in srgb,var(--meter-accent) 58%,transparent); outline-offset: 1px; }
      .dsh-usage-summary small { color: var(--meter-muted); font-size: 9px; }
      .dsh-usage-divider { width: 1px; height: 10px; background: var(--meter-border); }
      .dsh-usage-live { display: flex; align-items: center; gap: 5px; color: var(--meter-muted); }
      .dsh-usage-live-rate { white-space: nowrap; font-variant-numeric: tabular-nums; }
      .dsh-usage-live-rate::after { content: ""; display: inline-block; width: 0; }
      .dsh-usage-live-rate[data-digits="1"]::after { width: 2ch; }
      .dsh-usage-live-rate[data-digits="2"]::after { width: 1ch; }
      .dsh-usage-live i { width: 5px; height: 5px; border-radius: 50%; background: #a5abb4; box-shadow: 0 0 0 2px color-mix(in srgb,#a5abb4 12%,transparent); }
      .dsh-usage-live i.is-running { background: #32b36b; box-shadow: 0 0 0 2px color-mix(in srgb,#32b36b 16%,transparent); }
      .dsh-usage-pulse { width: 6px; height: 6px; border-radius: 50%; background: var(--meter-accent); animation: dsh-usage-pulse 1.25s ease-in-out infinite; }
      @keyframes dsh-usage-pulse { 50% { opacity: .3; transform: scale(.75); } }
      .dsh-usage-popover { position: absolute; top: 34px; left: calc(50% - 174px); width: 348px; box-sizing: border-box; padding: 6px; border: 1px solid var(--meter-border); border-radius: 12px; background: var(--meter-layer); box-shadow: 0 12px 36px rgba(10,16,28,.15),0 2px 7px rgba(10,16,28,.07); opacity: 0; visibility: hidden; pointer-events: none; transition: opacity 130ms ease,visibility 130ms; color: inherit; font-size: 11px; line-height: 1.3; }
      .dsh-usage-popover[data-open="true"] { opacity: 1; visibility: visible; pointer-events: auto; }
      .dsh-usage-popover-head { display: grid; grid-template-columns: 1.2fr .8fr; overflow: hidden; border-radius: 8px; background: var(--meter-subtle); box-shadow: 0 0 0 1px var(--meter-border) inset; }
      .dsh-usage-popover-head > div { display: flex; align-items: baseline; justify-content: space-between; padding: 8px 10px; }
      .dsh-usage-popover-head > div + div { border-left: 1px solid var(--meter-border); }
      .dsh-usage-popover-head span, .dsh-usage-cost span { color: var(--meter-muted); }
      .dsh-usage-popover-head span { font-size: 10px; }
      .dsh-usage-popover-head strong { font-size: 15px; font-variant-numeric: tabular-nums; letter-spacing: -.02em; }
      .dsh-usage-popover-head small { color: var(--meter-muted); font-size: 8px; font-weight: 500; letter-spacing: 0; }
      .dsh-usage-period { padding: 10px 7px 9px; border-bottom: 1px solid var(--meter-border); }
      .dsh-usage-period:last-of-type { border-bottom: 0; padding-bottom: 7px; }
      .dsh-usage-period-head, .dsh-usage-cost { display: flex; align-items: baseline; justify-content: space-between; }
      .dsh-usage-period-head span { font-size: 11px; font-weight: 650; letter-spacing: .01em; }
      .dsh-usage-period-head strong { font-size: 15px; font-variant-numeric: tabular-nums; letter-spacing: -.01em; }
      .dsh-usage-cost { margin-top: 2px; }
      .dsh-usage-cost strong { color: var(--meter-accent); font-size: 11px; font-variant-numeric: tabular-nums; }
      .dsh-usage-breakdown { display: grid; grid-template-columns: 1fr 1fr; gap: 4px 12px; margin: 8px 0 0; font-size: 10.5px; }
      .dsh-usage-breakdown div { display: flex; align-items: center; justify-content: space-between; gap: 6px; min-width: 0; }
      .dsh-usage-breakdown dt { color: var(--meter-muted); }
      .dsh-usage-breakdown dd { margin: 0; font-variant-numeric: tabular-nums; white-space: nowrap; }
      .dsh-usage-warning { margin: 7px 0 0; color: #bd6a28; font-size: 9px; }
      .dsh-usage-scan-warning { margin: 10px 8px 4px; color: #bd6a28; font-size: 10px; line-height: 1.45; }
      body[data-ds-dark-theme] .dsh-usage-warning { color: #e4a263; }
      body[data-ds-dark-theme] .dsh-usage-scan-warning { color: #e4a263; }
      .dsh-usage-empty { margin: 0; padding: 22px 8px; text-align: center; color: var(--meter-muted); }
      @media (max-width: 420px) { .dsh-usage-popover { left: 16px; width: calc(100vw - 32px); } }
      @media (max-width: 1080px) { .dsh-usage-today small, .dsh-usage-live i { display: none; } .dsh-usage-summary { gap: 6px; padding: 0 8px; } }
      @media (prefers-reduced-motion: reduce) { .dsh-usage-popover, .dsh-usage-pulse { animation: none; transition: none; } }
    `
    document.head.append(style)
  }

  function installUi() {
    installStyle()
    document.body.classList.add('dsh-native-titlebar-overlay')
    host = document.createElement('div')
    host.className = 'dsh-usage-meter'
    host.innerHTML = `
      <button class="dsh-usage-summary" type="button" aria-haspopup="dialog" aria-expanded="false">
        <span class="dsh-usage-pulse"></span><span>${t.loading}</span>
      </button>
      <div class="dsh-usage-popover" role="dialog" aria-label="${t.tokens}" data-open="false"></div>`
    document.body.append(host)
    summaryButton = host.querySelector('.dsh-usage-summary')
    popover = host.querySelector('.dsh-usage-popover')
    summaryButton.addEventListener('click', event => {
      event.stopPropagation()
      const open = popover.dataset.open !== 'true'
      popover.dataset.open = String(open)
      summaryButton.setAttribute('aria-expanded', String(open))
    })
    popover.addEventListener('click', event => event.stopPropagation())
    document.addEventListener('click', () => {
      popover.dataset.open = 'false'
      summaryButton.setAttribute('aria-expanded', 'false')
    })
    document.addEventListener('keydown', event => {
      if (event.key !== 'Escape') return
      popover.dataset.open = 'false'
      summaryButton.setAttribute('aria-expanded', 'false')
      summaryButton.focus()
    })
    window.setInterval(render, 500)
    render()
  }

  function handleDesktopEvent(event) {
    const detail = event?.detail
    if (detail?.type === 'usage-snapshot') {
      for (const record of detail.payload?.records || []) {
        if (record?.id) records.set(record.id, record)
      }
      scanWarnings = number(detail.payload?.warnings)
      snapshotLoaded = true
      scheduleRender()
    } else if (detail?.type === 'usage-snapshot-error') {
      console.warn('[dsh-usage] local usage scan failed:', detail.payload?.message)
      snapshotLoaded = true
      scanWarnings += 1
      scheduleRender()
    }
  }

  function start() {
    if (!document.body || document.querySelector('.dsh-usage-meter')) return
    installUi()
    window.addEventListener('dsh-desktop-event', handleDesktopEvent)
    const stopMux = openDownlink('/api/events.mux', frame => {
      if (frame?.type === 'session/event') handleSessionEvent(frame.sessionId, frame.event)
      else if (frame?.type === 'session/projection' && frame.key === 'sessionStats') {
        sessionStatsById.set(frame.sessionId, frame.value)
        scheduleRender()
      }
    })
    const stopHost = openDownlink('/api/events.host', frame => {
      if (frame?.type === 'host/session-status') {
        if (frame.running) runningSessions.add(frame.sessionId)
        else runningSessions.delete(frame.sessionId)
        scheduleRender()
      } else if (frame?.type === 'host/session-removed') {
        runningSessions.delete(frame.sessionId)
        scheduleRender()
      }
    })
    window.addEventListener('beforeunload', () => { stopMux(); stopHost() }, { once: true })
    void loadOpenRouterPricing()
    void loadRunningSessions()
    window.setTimeout(requestSnapshot, 150)
  }

  if (document.readyState === 'complete') start()
  else window.addEventListener('load', start, { once: true })
})()
