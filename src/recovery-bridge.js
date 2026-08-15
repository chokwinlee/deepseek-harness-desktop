/**
 * Capability bridge between the first-party Desktop Settings plugin and the
 * native Tauri host. Normal plugin management is rendered by DSH Settings;
 * this layer owns only privileged actions and cross-screen recovery notices.
 */
(() => {
  'use strict'

  if (typeof window === 'undefined' || typeof document === 'undefined') return
  if (location.protocol !== 'http:' || location.hostname !== '127.0.0.1') return

  const ACTION_TOKEN = '__DSH_ACTION_TOKEN__'
  const BRIDGE_KEY = '__DSH_DESKTOP_PLUGIN_MANAGER__'
  const LAYER_ID = 'dsh-desktop-notices'
  const ALLOWED_ACTIONS = new Set([
    'status',
    'install-plugin',
    'remove-plugin',
    'restart-harness',
    'install-cli',
    'remove-cli',
  ])
  const params = new URLSearchParams(location.search)
  const subscribers = new Set()
  let snapshot = Object.freeze({ status: null, busyOperation: '', error: '' })
  let layer = null
  let shadow = null
  let lastPendingKey = ''
  let verifyingNotice = null

  function publish(next) {
    snapshot = Object.freeze({ ...snapshot, ...next })
    for (const subscriber of [...subscribers]) {
      try { subscriber() } catch {}
    }
  }

  function actionUrl(action, values = {}) {
    if (!ALLOWED_ACTIONS.has(action)) throw new Error(`Unsupported Desktop action: ${action}`)
    const query = new URLSearchParams({ token: ACTION_TOKEN })
    for (const [key, value] of Object.entries(values)) {
      if (value !== undefined && value !== null) query.set(key, String(value))
    }
    return `dsh-desktop://action/${action}?${query.toString()}`
  }

  function request(action, values) {
    location.assign(actionUrl(action, values))
  }

  const bridge = Object.freeze({
    request,
    getSnapshot: () => snapshot,
    subscribe(subscriber) {
      subscribers.add(subscriber)
      return () => subscribers.delete(subscriber)
    },
  })
  Object.defineProperty(window, BRIDGE_KEY, {
    value: bridge,
    configurable: false,
    enumerable: false,
    writable: false,
  })

  function mountNoticeLayer() {
    if (layer) return
    layer = document.createElement('div')
    layer.id = LAYER_ID
    layer.setAttribute('aria-live', 'polite')
    shadow = layer.attachShadow({ mode: 'closed' })
    shadow.innerHTML = `
      <style>
        :host { all:initial; }
        * { box-sizing:border-box; }
        .stack { position:fixed; z-index:2147483001; top:12px; right:16px; display:grid; gap:9px; width:min(520px,calc(100vw - 32px)); pointer-events:none; }
        .notice { display:flex; align-items:center; gap:12px; padding:11px 12px; border:1px solid color-mix(in srgb,var(--dsw-alias-state-business-primary,#2563eb) 24%,transparent); border-radius:12px; background:var(--dsw-alias-bg-layer-3,#f8fafc); color:var(--dsw-alias-label-primary,#172033); box-shadow:0 12px 34px rgba(15,23,42,.16); font:12px/1.45 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif; pointer-events:auto; }
        .notice[data-tone="warning"] { border-color:rgba(217,119,6,.3); }
        .notice[data-tone="error"] { border-color:rgba(220,38,38,.28); }
        .copy { flex:1; min-width:0; }
        strong,span { display:block; }
        span { margin-top:1px; color:var(--dsw-alias-label-tertiary,#64748b); }
        .actions { display:flex; flex:none; gap:6px; }
        button { min-height:31px; padding:6px 9px; border:0; border-radius:8px; cursor:pointer; font:600 11px/1.4 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif; }
        button:focus-visible { outline:2px solid var(--dsw-alias-state-business-primary,#2563eb); outline-offset:2px; }
        .primary { background:var(--dsw-alias-label-primary,#172033); color:var(--dsw-alias-bg-layer-3,#f8fafc); }
        .secondary { background:var(--dsw-alias-bg-layer-1,#e9eef5); color:var(--dsw-alias-label-secondary,#334155); }
      </style>
      <div class="stack"></div>
    `
    document.body.append(layer)
  }

  function showNotice({ tone = 'info', title, body, primary, secondary, timeout = 0 }) {
    mountNoticeLayer()
    const notice = document.createElement('div')
    notice.className = 'notice'
    notice.dataset.tone = tone
    const copy = document.createElement('div')
    copy.className = 'copy'
    const strong = document.createElement('strong')
    strong.textContent = title
    const span = document.createElement('span')
    span.textContent = body
    copy.append(strong, span)
    notice.append(copy)
    if (primary || secondary) {
      const actions = document.createElement('div')
      actions.className = 'actions'
      for (const [kind, action] of [['secondary', secondary], ['primary', primary]]) {
        if (!action) continue
        const button = document.createElement('button')
        button.type = 'button'
        button.className = kind
        button.textContent = action.label
        button.addEventListener('click', () => action.run(notice, button))
        actions.append(button)
      }
      notice.append(actions)
    }
    shadow.querySelector('.stack').append(notice)
    if (timeout) window.setTimeout(() => notice.remove(), timeout)
    return notice
  }

  function pendingLabel(pending) {
    return pending?.changes?.[0]?.name || pending?.packages?.[0] || pending?.spec || '插件配置'
  }

  function clearVerifyingNotice() {
    verifyingNotice?.remove()
    verifyingNotice = null
  }

  function showPendingNotice(pending) {
    if (!pending || pending.state === 'verifying') return
    const label = pendingLabel(pending)
    const key = `${pending.updatedAtUnixMs || ''}:${pending.state || ''}:${label}`
    if (key === lastPendingKey) return
    lastPendingKey = key
    const fromCli = pending.source === 'cli'
    showNotice({
      title: fromCli ? `检测到命令行插件变更：${label}` : `${label} 已变更`,
      body: '请前往“设置 → 插件 → 安装与管理”检查并重启 DSH。',
      secondary: { label: '稍后', run: notice => notice.remove() },
      primary: {
        label: '立即重启',
        run: (notice, button) => {
          button.disabled = true
          notice.querySelector('strong').textContent = '正在重启 DSH…'
          notice.querySelector('span').textContent = '桌面窗口会保持打开，并验证新的插件配置。'
          request('restart-harness')
        },
      },
    })
  }

  function handleInitialNotice() {
    const rollback = params.get('dsh-desktop-plugin-rollback')
    const verifying = params.get('dsh-desktop-plugin-verifying')
    if (rollback) {
      showNotice({ tone: 'warning', title: '插件未通过启动验证，已自动恢复', body: `${rollback} 没有启用；此前可用的 profile 已恢复。`, timeout: 10_000 })
    } else if (verifying) {
      verifyingNotice = showNotice({ title: `正在验证 ${verifying}`, body: '稳定运行五秒后才会保存为最近可用配置。' })
    }
    if (params.get('dsh-desktop-safe-mode') === '1') {
      showNotice({
        tone: 'warning',
        title: 'Harness 正在安全模式下运行',
        body: '第三方 Bundle 暂未加载，原配置没有被删除。',
        primary: { label: '尝试正常启动', run: () => location.assign('__DSH_RECOVERY_URL__?dsh-desktop-action=retry') },
      })
    }
  }

  window.addEventListener('dsh-desktop-event', event => {
    const detail = event.detail || {}
    const payload = detail.payload || {}
    if (detail.type === 'desktop-status') {
      publish({ status: payload, busyOperation: '', error: '' })
      if (payload.pending?.state !== 'verifying') clearVerifyingNotice()
      if (payload.pending?.state === 'restart-required') showPendingNotice(payload.pending)
      return
    }
    if (detail.type === 'operation-started') {
      publish({ busyOperation: payload.operation || 'operation', error: '' })
      return
    }
    if (detail.type === 'plugin-installed' || detail.type === 'plugin-removed') {
      publish({ status: payload, busyOperation: '', error: '' })
      showPendingNotice(payload.pending)
      return
    }
    if (detail.type === 'plugin-change-detected') {
      publish({ status: { ...(snapshot.status || {}), pending: payload } })
      showPendingNotice(payload)
      return
    }
    if (detail.type === 'plugin-verified') {
      lastPendingKey = ''
      clearVerifyingNotice()
      publish({ status: { ...(snapshot.status || {}), pending: null }, busyOperation: '', error: '' })
      const label = payload.label || '插件配置'
      const messages = {
        removed: { title: `${label} 已移除`, body: '卸载验证通过，当前配置已保存为最近可用配置。' },
        updated: { title: `${label} 已更新`, body: '更新验证通过，当前配置已保存为最近可用配置。' },
        disabled: { title: `${label} 已停用`, body: '停用验证通过，当前配置已保存为最近可用配置。' },
        enabled: { title: `${label} 已启用`, body: '启动验证通过，已保存为最近可用配置。' },
        changed: { title: `${label} 变更已生效`, body: '启动验证通过，当前配置已保存为最近可用配置。' },
      }
      showNotice({ ...(messages[payload.outcome] || messages.changed), timeout: 8_000 })
      request('status')
      return
    }
    if (detail.type === 'cli-status') {
      publish({ status: { ...(snapshot.status || {}), cli: payload }, busyOperation: '', error: '' })
      return
    }
    if (detail.type === 'operation-error') {
      publish({ busyOperation: '', error: payload.message || '操作未能完成。' })
      showNotice({ tone: 'error', title: '插件操作未能完成', body: payload.message || '请稍后重试。', timeout: 10_000 })
    }
  })

  function startBridge() {
    handleInitialNotice()
    // This script is injected at document start. Navigating to the custom
    // action protocol before WKWebView finishes its initial HTTP navigation
    // cancels the page load and leaves the Desktop window blank. Wait for the
    // Harness document and module scripts to finish before requesting status.
    window.setTimeout(() => request('status'), 0)
  }

  if (document.readyState === 'complete') {
    startBridge()
  } else {
    window.addEventListener('load', startBridge, { once: true })
  }
})()
