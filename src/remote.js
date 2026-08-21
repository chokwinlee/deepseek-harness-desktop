/**
 * First-party Mobile Remote controls for the native Desktop shell.
 *
 * The Web UI can request status or an explicit enable/disable transition, but
 * it never receives shell access or Tailscale credentials. The native host
 * validates every action and owns the LAN proxy, Harness, and Serve processes.
 */
(() => {
  'use strict'

  const TEST_FLAG = '__DSH_REMOTE_TEST__'
  const TEST_API = '__DSH_REMOTE_TEST_API__'
  const ACTION_TOKEN = '__DSH_ACTION_TOKEN__'
  const SETTINGS_SLOT_SELECTOR = '[data-slot="settings.general.item"]'
  const SETTING_ID = 'dsh-desktop-remote-setting'
  const STYLE_ID = 'dsh-desktop-remote-style'
  const LAYER_ID = 'dsh-desktop-remote-layer'
  const STATUS_POLL_INTERVAL_MS = 10000
  const STATUS_REQUEST_TIMEOUT_MS = 6000
  const ACTION_ACK_TIMEOUT_MS = 8000
  const LAN_TRANSPORT = 'lan'
  const TAILSCALE_TRANSPORT = 'tailscale'
  const ALLOWED_ACTIONS = new Set([
    'remote-status',
    'remote-open-https',
    'remote-enable',
    'remote-disable',
    'remote-lan-enable',
    'remote-lan-disable',
  ])

  function languageFromTag(tag) {
    return String(tag || '').toLowerCase().startsWith('zh') ? 'zh' : 'en'
  }

  function actionUrl(action, token = ACTION_TOKEN, parameters = {}) {
    if (!ALLOWED_ACTIONS.has(action)) throw new Error(`Unsupported Remote action: ${action}`)
    const query = new URLSearchParams({ token })
    for (const [name, value] of Object.entries(parameters)) {
      if (value !== undefined && value !== null && value !== '') query.set(name, String(value))
    }
    return `dsh-desktop://action/${action}?${query.toString()}`
  }

  function normalizeStatus(value) {
    const status = value && typeof value === 'object' ? value : {}
    return Object.freeze({
      phase: String(status.phase || 'off'),
      installed: Boolean(status.installed),
      backendState: String(status.backendState || ''),
      magicDNS: Boolean(status.magicDNS),
      httpsReady: Boolean(status.httpsReady),
      enabled: Boolean(status.enabled),
      busy: Boolean(status.busy),
      dnsName: String(status.dnsName || ''),
      url: String(status.url || ''),
      pairingURL: String(status.pairingURL || ''),
      qrSvg: String(status.qrSvg || ''),
      error: String(status.error || ''),
      port: Number(status.port) || 8443,
      lanAvailable: Boolean(status.lanAvailable),
      lanEnabled: Boolean(status.lanEnabled),
      lanBusy: Boolean(status.lanBusy),
      lanURL: String(status.lanURL || ''),
      lanPairingURL: String(status.lanPairingURL || ''),
      lanQrSvg: String(status.lanQrSvg || ''),
      lanError: String(status.lanError || ''),
      lanPort: Number(status.lanPort) || 8765,
    })
  }

  function shouldPollStatus(value, settingVisible, pageVisible = true, requestInFlight = false) {
    const next = normalizeStatus(value)
    return Boolean(settingVisible)
      && Boolean(pageVisible)
      && !requestInFlight
      && !next.busy
      && !next.lanBusy
  }

  function copyFor(language) {
    return language === 'zh'
      ? {
          title: '手机 Remote',
          description: '在 iPhone 上继续查看这台电脑里的项目、会话和正在运行的任务。',
          connect: '连接 iPhone',
          manage: '管理连接',
          managerBody: '优先使用同一 Wi-Fi；只有离开本地网络时才需要 Tailscale。',
          lanSummaryActive: '同一 Wi-Fi 连接已开启，可随时重新显示配对码。',
          tailscaleSummaryActive: '跨网络连接已开启；同一 Wi-Fi 配对仍可独立使用。',
          bothSummaryActive: '同一 Wi-Fi 与跨网络连接均已开启。',
          lanTitle: '同一 Wi-Fi',
          lanBadge: '推荐',
          lanDescription: 'iPhone 与电脑连接同一个可信 Wi-Fi，无需安装或配置 Tailscale。',
          lanUnavailable: 'Harness 启动完成后即可开始本地配对。',
          lanActive: '本地连接已开启：{url}',
          lanStart: '开始本地配对',
          lanStarting: '正在准备本地连接…',
          lanStop: '关闭本地连接',
          lanStopping: '正在关闭本地连接…',
          lanPair: '显示配对码',
          tailscaleTitle: '跨网络连接',
          tailscaleBadge: '可选',
          tailscaleDescription: '离开本地 Wi-Fi 时，通过你自己的 Tailscale 网络连接。',
          unavailable: '需要先在电脑和 iPhone 安装 Tailscale，并登录同一个 Tailnet。',
          disconnected: 'Tailscale 尚未连接；这不会影响同一 Wi-Fi 配对。',
          magicDNS: '当前 Tailnet 需要开启 MagicDNS；这不会影响同一 Wi-Fi 配对。',
          https: '还需在 Tailscale 管理页启用 HTTPS。',
          setupHTTPS: '设置 HTTPS',
          active: '跨网络连接已开启：{url}',
          enable: '开启跨网络',
          enabling: '正在开启跨网络连接…',
          disable: '关闭跨网络',
          disabling: '正在关闭跨网络连接…',
          pair: '显示配对码',
          restart: '开启跨网络连接会重启 Harness，并中断正在运行的任务。',
          modalTitle: '跨网络配对',
          lanModalTitle: '同一 Wi-Fi 配对',
          modalBody: '在 DSH Remote 中扫描二维码。电脑和 iPhone 必须登录同一个 Tailnet。',
          lanModalBody: '让 iPhone 与电脑连接同一个受信任的 Wi-Fi，然后扫描二维码。配对凭据只会显示在二维码中。',
          address: '电脑地址',
          copy: '复制配对链接',
          copied: '已复制',
          close: '完成',
          managerClose: '关闭',
          back: '返回连接方式',
        }
      : {
          title: 'Mobile Remote',
          description: 'Continue with this computer’s projects, sessions, and running tasks from iPhone.',
          connect: 'Connect iPhone',
          manage: 'Manage connections',
          managerBody: 'Use the same Wi-Fi first. Tailscale is only needed away from the local network.',
          lanSummaryActive: 'Same Wi-Fi is on. You can show the pairing code again at any time.',
          tailscaleSummaryActive: 'Anywhere access is on. Same Wi-Fi pairing remains independently available.',
          bothSummaryActive: 'Same Wi-Fi and anywhere access are both on.',
          lanTitle: 'Same Wi-Fi',
          lanBadge: 'Recommended',
          lanDescription: 'Connect iPhone and this computer to the same trusted Wi-Fi. Tailscale is not required.',
          lanUnavailable: 'Local pairing is available after Harness finishes starting.',
          lanActive: 'Local connection is on: {url}',
          lanStart: 'Start local pairing',
          lanStarting: 'Preparing local connection…',
          lanStop: 'Turn off local connection',
          lanStopping: 'Turning off local connection…',
          lanPair: 'Show pairing code',
          tailscaleTitle: 'Connect from anywhere',
          tailscaleBadge: 'Optional',
          tailscaleDescription: 'Use your own Tailscale network when iPhone is away from local Wi-Fi.',
          unavailable: 'Install Tailscale on this computer and iPhone, then sign in to the same tailnet.',
          disconnected: 'Tailscale is not connected. Same Wi-Fi pairing is still available.',
          magicDNS: 'MagicDNS must be enabled for this tailnet. Same Wi-Fi pairing is unaffected.',
          https: 'Enable HTTPS in the Tailscale admin console to continue.',
          setupHTTPS: 'Set up HTTPS',
          active: 'Anywhere connection is on: {url}',
          enable: 'Connect from anywhere',
          enabling: 'Preparing anywhere connection…',
          disable: 'Turn off anywhere access',
          disabling: 'Turning off anywhere access…',
          pair: 'Show pairing code',
          restart: 'Turning on anywhere access restarts Harness and interrupts running tasks.',
          modalTitle: 'Pair from anywhere',
          lanModalTitle: 'Pair on the same Wi-Fi',
          modalBody: 'Scan this QR code in DSH Remote. Both devices must use the same tailnet.',
          lanModalBody: 'Connect iPhone and this computer to the same trusted Wi-Fi, then scan. The pairing credential is only carried by the QR code.',
          address: 'Computer address',
          copy: 'Copy pairing link',
          copied: 'Copied',
          close: 'Done',
          managerClose: 'Close',
          back: 'Back to connection options',
        }
  }

  function transportViewState(value, transport, language = 'en', pendingAction = '') {
    const next = normalizeStatus(value)
    const copy = copyFor(languageFromTag(language))
    const lan = transport === LAN_TRANSPORT
    const enabled = lan ? next.lanEnabled : next.enabled
    const nativeBusy = lan ? next.lanBusy : next.busy
    const busy = nativeBusy || Boolean(pendingAction)
    const endpoint = lan ? next.lanURL : next.url
    const error = lan ? next.lanError : next.error
    const stopping = pendingAction.endsWith('-disable')
      || (!pendingAction && nativeBusy && enabled)
      || (!lan && next.phase === 'stopping')

    let description
    let hasError = false
    if (busy) {
      description = lan
        ? stopping ? copy.lanStopping : copy.lanStarting
        : stopping ? copy.disabling : copy.enabling
    } else if (error) {
      description = error
      hasError = true
    } else if (enabled) {
      description = (lan ? copy.lanActive : copy.active).replace('{url}', endpoint)
    } else if (lan) {
      description = next.lanAvailable ? copy.lanDescription : copy.lanUnavailable
    } else if (!next.installed) {
      description = copy.unavailable
    } else if (next.backendState !== 'Running') {
      description = copy.disconnected
    } else if (!next.magicDNS) {
      description = copy.magicDNS
    } else if (!next.httpsReady) {
      description = copy.https
    } else {
      description = `${copy.tailscaleDescription} ${copy.restart}`
    }

    let action
    let actionLabel
    let actionDisabled = busy
    if (lan) {
      action = enabled ? 'remote-lan-disable' : 'remote-lan-enable'
      actionLabel = busy
        ? stopping ? copy.lanStopping : copy.lanStarting
        : enabled ? copy.lanStop : copy.lanStart
      actionDisabled ||= !enabled && !next.lanAvailable
    } else if (enabled) {
      action = 'remote-disable'
      actionLabel = busy ? copy.disabling : copy.disable
    } else if (next.installed
      && next.backendState === 'Running'
      && next.magicDNS
      && !next.httpsReady) {
      action = 'remote-open-https'
      actionLabel = copy.setupHTTPS
    } else {
      action = 'remote-enable'
      actionLabel = busy ? copy.enabling : copy.enable
      actionDisabled ||= !(next.installed
        && next.backendState === 'Running'
        && next.magicDNS
        && next.httpsReady)
    }

    return Object.freeze({
      action,
      actionDisabled,
      actionLabel,
      busy,
      description,
      enabled,
      hasError,
      pairDisabled: busy || !(lan ? next.lanQrSvg : next.qrSvg),
      pairLabel: lan ? copy.lanPair : copy.pair,
    })
  }

  function statusAfterError(value, transport, message) {
    const next = normalizeStatus(value)
    if (transport === LAN_TRANSPORT) {
      return normalizeStatus({ ...next, lanBusy: false, lanError: message })
    }
    return normalizeStatus({ ...next, busy: false, phase: 'error', error: message })
  }

  function pendingActionAfterStatus(pendingAction, value, transport) {
    if (!pendingAction) return ''
    const next = normalizeStatus(value)
    const lan = transport === LAN_TRANSPORT
    const busy = lan ? next.lanBusy : next.busy
    const enabled = lan ? next.lanEnabled : next.enabled
    if (busy) return ''
    if (pendingAction.endsWith('-enable') && enabled) return ''
    if (pendingAction.endsWith('-disable') && !enabled) return ''
    return pendingAction
  }

  const testGlobal = typeof globalThis === 'undefined' ? null : globalThis
  if (testGlobal?.[TEST_FLAG] === true) {
    testGlobal[TEST_API] = Object.freeze({
      actionUrl,
      copyFor,
      languageFromTag,
      normalizeStatus,
      pendingActionAfterStatus,
      shouldPollStatus,
      statusAfterError,
      transportViewState,
    })
    return
  }

  if (typeof window === 'undefined' || typeof document === 'undefined') return
  if (location.protocol !== 'http:' || location.hostname !== '127.0.0.1') return

  let status = normalizeStatus()
  let settingRow = null
  let settingTitle = null
  let settingDescription = null
  let settingConnectButton = null
  let lanRoute = null
  let lanDescription = null
  let lanActionButton = null
  let lanPairButton = null
  let tailscaleRoute = null
  let tailscaleDescription = null
  let tailscaleActionButton = null
  let tailscalePairButton = null
  let layer = null
  let layerShadow = null
  let observer = null
  let mountFrame = 0
  let pairingTransport = TAILSCALE_TRANSPORT
  let lastActionTransport = TAILSCALE_TRANSPORT
  let pendingLanAction = ''
  let pendingTailscaleAction = ''
  let pendingLanTimer = 0
  let pendingTailscaleTimer = 0
  let statusRequestInFlight = false
  let statusRequestTimer = 0
  let pairingReturnFocus = null

  function currentLanguage() {
    return languageFromTag(document.documentElement.lang || navigator.language)
  }

  function request(action, parameters) {
    location.assign(actionUrl(action, ACTION_TOKEN, parameters))
  }

  function clearPendingAction(transport) {
    if (transport === LAN_TRANSPORT) {
      pendingLanAction = ''
      if (pendingLanTimer) window.clearTimeout(pendingLanTimer)
      pendingLanTimer = 0
    } else {
      pendingTailscaleAction = ''
      if (pendingTailscaleTimer) window.clearTimeout(pendingTailscaleTimer)
      pendingTailscaleTimer = 0
    }
  }

  function setPendingAction(transport, action) {
    clearPendingAction(transport)
    if (transport === LAN_TRANSPORT) pendingLanAction = action
    else pendingTailscaleAction = action
    const timeout = window.setTimeout(() => {
      clearPendingAction(transport)
      updateSetting()
      refreshStatus(true)
    }, ACTION_ACK_TIMEOUT_MS)
    if (transport === LAN_TRANSPORT) pendingLanTimer = timeout
    else pendingTailscaleTimer = timeout
  }

  function requestTransportAction(action, transport) {
    lastActionTransport = transport
    if (action !== 'remote-open-https') {
      setPendingAction(transport, action)
      updateSetting()
    }
    try {
      request(action)
    } catch (error) {
      clearPendingAction(transport)
      updateSetting()
      throw error
    }
  }

  function installStyle() {
    if (document.getElementById(STYLE_ID)) return
    const style = document.createElement('style')
    style.id = STYLE_ID
    style.textContent = `
      #${SETTING_ID}{box-sizing:border-box;border-bottom:1px solid var(--dsw-alias-border-l2);display:flex;align-items:center;gap:18px;width:100%;padding:16px 0;color:var(--dsw-alias-label-primary);font:inherit}
      #${SETTING_ID} *{box-sizing:border-box}
      #${SETTING_ID} .dsh-remote-heading{display:flex;flex:1;min-width:0;flex-direction:column;gap:3px}
      #${SETTING_ID} .dsh-remote-title{color:var(--dsw-alias-label-primary);font-size:14px;font-weight:500;line-height:21px}
      #${SETTING_ID} .dsh-remote-intro{max-width:680px;color:var(--dsw-alias-label-tertiary);font-size:12px;font-weight:400;line-height:18px}
      #${SETTING_ID} button{box-sizing:border-box;border:1px solid var(--dsw-alias-label-primary);border-radius:9px;min-height:34px;padding:6px 12px;background:var(--dsw-alias-label-primary);color:var(--dsw-alias-bg-layer-3);cursor:pointer;font:inherit;font-size:12px;font-weight:600;line-height:18px;white-space:nowrap;transition:transform 100ms ease-out,opacity 120ms ease}
      #${SETTING_ID} button:active:not(:disabled){transform:scale(.97)}
      #${SETTING_ID} button:focus-visible{outline:2px solid var(--dsw-alias-state-business-primary);outline-offset:2px}
      @media(max-width:620px){#${SETTING_ID}{align-items:flex-start;flex-direction:column}#${SETTING_ID} button{align-self:flex-end}}
      @media(prefers-reduced-motion:reduce){#${SETTING_ID} button{transition:none}#${SETTING_ID} button:active:not(:disabled){transform:none}}
    `
    ;(document.head || document.documentElement).append(style)
  }

  function createButton(label, className, action, disabled = false) {
    const button = document.createElement('button')
    button.type = 'button'
    button.className = className
    button.textContent = label
    button.setAttribute('aria-label', label)
    button.disabled = disabled
    button.addEventListener('click', action)
    return button
  }

  function configureButton(button, label, className, disabled, hidden = false) {
    button.textContent = label
    button.setAttribute('aria-label', label)
    button.className = className
    button.disabled = disabled
    button.hidden = hidden
  }

  function renderTransport(transport, view) {
    const lan = transport === LAN_TRANSPORT
    const route = lan ? lanRoute : tailscaleRoute
    const description = lan ? lanDescription : tailscaleDescription
    const actionButton = lan ? lanActionButton : tailscaleActionButton
    const pairButton = lan ? lanPairButton : tailscalePairButton
    if (!route || !description || !actionButton || !pairButton) return

    description.textContent = view.description
    route.toggleAttribute('data-busy', view.busy)
    route.toggleAttribute('data-error', view.hasError)
    route.setAttribute('aria-busy', String(view.busy))
    configureButton(
      actionButton,
      view.actionLabel,
      view.enabled || !lan ? '' : 'dsh-remote-primary',
      view.actionDisabled,
    )
    configureButton(pairButton, view.pairLabel, 'dsh-remote-primary', view.pairDisabled, !view.enabled)
  }

  function updateSetting() {
    if (!settingRow || !settingTitle || !settingDescription || !settingConnectButton) return
    const copy = copyFor(currentLanguage())
    const lanView = transportViewState(status, LAN_TRANSPORT, currentLanguage(), pendingLanAction)
    const tailscaleView = transportViewState(
      status,
      TAILSCALE_TRANSPORT,
      currentLanguage(),
      pendingTailscaleAction,
    )
    settingTitle.textContent = copy.title
    if (lanView.busy) settingDescription.textContent = lanView.description
    else if (tailscaleView.busy) settingDescription.textContent = tailscaleView.description
    else if (status.lanEnabled && status.enabled) settingDescription.textContent = copy.bothSummaryActive
    else if (status.lanEnabled) settingDescription.textContent = copy.lanSummaryActive
    else if (status.enabled) settingDescription.textContent = copy.tailscaleSummaryActive
    else settingDescription.textContent = copy.description
    const hasActiveConnection = status.enabled
      || status.lanEnabled
      || status.busy
      || status.lanBusy
      || pendingLanAction
      || pendingTailscaleAction
    settingConnectButton.textContent = hasActiveConnection ? copy.manage : copy.connect
    settingConnectButton.setAttribute('aria-label', settingConnectButton.textContent)
    if (!lanRoute || !tailscaleRoute) return
    lanRoute.querySelector('.dsh-remote-route-title').textContent = copy.lanTitle
    lanRoute.querySelector('.dsh-remote-badge').textContent = copy.lanBadge
    tailscaleRoute.querySelector('.dsh-remote-route-title').textContent = copy.tailscaleTitle
    tailscaleRoute.querySelector('.dsh-remote-badge').textContent = copy.tailscaleBadge
    renderTransport(LAN_TRANSPORT, lanView)
    renderTransport(TAILSCALE_TRANSPORT, tailscaleView)
  }

  function createTransportRoute(transport) {
    const route = document.createElement('section')
    route.className = 'dsh-remote-route'
    route.dataset.kind = transport
    const heading = document.createElement('div')
    heading.className = 'dsh-remote-route-heading'
    const title = document.createElement('h3')
    title.className = 'dsh-remote-route-title'
    const badge = document.createElement('span')
    badge.className = 'dsh-remote-badge'
    heading.append(title, badge)
    const description = document.createElement('p')
    description.className = 'dsh-remote-route-description'
    description.setAttribute('aria-live', 'polite')
    const controls = document.createElement('div')
    controls.className = 'dsh-remote-controls'
    const actionButton = createButton('', 'dsh-remote-primary', () => {
      const pendingAction = transport === LAN_TRANSPORT ? pendingLanAction : pendingTailscaleAction
      const view = transportViewState(status, transport, currentLanguage(), pendingAction)
      if (!view.actionDisabled) requestTransportAction(view.action, transport)
    })
    const pairButton = createButton('', 'dsh-remote-primary', () => openPairing(transport), true)
    controls.append(actionButton, pairButton)
    route.append(heading, description, controls)
    return { actionButton, description, pairButton, route }
  }

  function createSettingRow() {
    const row = document.createElement('section')
    row.id = SETTING_ID
    row.setAttribute('aria-labelledby', `${SETTING_ID}-title`)
    const heading = document.createElement('header')
    heading.className = 'dsh-remote-heading'
    settingTitle = document.createElement('div')
    settingTitle.className = 'dsh-remote-title'
    settingTitle.id = `${SETTING_ID}-title`
    settingDescription = document.createElement('div')
    settingDescription.className = 'dsh-remote-intro'
    heading.append(settingTitle, settingDescription)
    settingConnectButton = createButton('', '', openConnectionManager)
    row.append(heading, settingConnectButton)
    settingRow = row
    updateSetting()
    return row
  }

  function mountSetting() {
    const slot = document.querySelector(SETTINGS_SLOT_SELECTOR)
    if (!slot) return
    if (settingRow?.isConnected && settingRow.parentElement === slot) {
      updateSetting()
      return
    }
    document.getElementById(SETTING_ID)?.remove()
    slot.append(createSettingRow())
  }

  function ensureLayer() {
    if (layer) return
    layer = document.createElement('div')
    layer.id = LAYER_ID
    layerShadow = layer.attachShadow({ mode: 'closed' })
    layerShadow.innerHTML = `
      <style>
        :host{all:initial}:host([hidden]){display:none}*{box-sizing:border-box}[hidden]{display:none!important}.backdrop{position:fixed;z-index:2147483002;inset:0;display:grid;place-items:center;overflow:auto;padding:24px;background:rgba(9,16,29,.48);font:13px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}.dialog{width:min(560px,100%);max-height:calc(100vh - 48px);overflow:auto;border:1px solid var(--dsw-alias-border-l2,#dbe1ea);border-radius:18px;padding:22px;background:var(--dsw-alias-bg-layer-3,#fff);color:var(--dsw-alias-label-primary,#111827);box-shadow:0 24px 80px rgba(0,0,0,.28)}h2,p{margin:0}h2{font-size:19px;line-height:26px}.body{margin-top:6px;color:var(--dsw-alias-label-tertiary,#64748b)}.chooser-routes{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);gap:10px;margin-top:18px}.dsh-remote-route{min-width:0;border:1px solid var(--dsw-alias-border-l2,#dbe1ea);border-radius:13px;padding:13px;background:var(--dsw-alias-bg-layer-1,#f1f5f9);transition:border-color 160ms ease,background-color 160ms ease}.dsh-remote-route[data-kind="lan"]{border-color:color-mix(in srgb,var(--dsw-alias-state-business-primary,#2563eb) 32%,var(--dsw-alias-border-l2,#dbe1ea));background:color-mix(in srgb,var(--dsw-alias-state-business-primary,#2563eb) 5%,var(--dsw-alias-bg-layer-1,#f1f5f9))}.dsh-remote-route[data-busy]{border-color:var(--dsw-alias-state-business-primary,#2563eb)}.dsh-remote-route[data-error]{border-color:color-mix(in srgb,var(--dsw-alias-state-error-primary,#dc2626) 48%,var(--dsw-alias-border-l2,#dbe1ea))}.dsh-remote-route-heading{display:flex;align-items:center;gap:7px;min-height:20px}.dsh-remote-route-title{margin:0;color:var(--dsw-alias-label-primary,#111827);font-size:13px;font-weight:600;line-height:20px}.dsh-remote-badge{border-radius:999px;padding:1px 7px;background:var(--dsw-alias-bg-layer-3,#fff);color:var(--dsw-alias-label-tertiary,#64748b);font-size:10px;font-weight:600;line-height:17px}.dsh-remote-route[data-kind="lan"] .dsh-remote-badge{background:color-mix(in srgb,var(--dsw-alias-state-business-primary,#2563eb) 12%,transparent);color:var(--dsw-alias-state-business-primary,#2563eb)}.dsh-remote-route-description{min-height:54px;margin:5px 0 0;color:var(--dsw-alias-label-tertiary,#64748b);font-size:12px;line-height:18px;overflow-wrap:anywhere}.dsh-remote-route[data-error] .dsh-remote-route-description{color:var(--dsw-alias-state-error-primary,#dc2626)}.dsh-remote-controls{display:flex;align-items:center;justify-content:flex-end;gap:7px;margin-top:12px}.qr{display:block;width:248px;height:248px;margin:20px auto 16px;border:10px solid #fff;border-radius:14px;background:#fff}.label{margin-top:6px;color:var(--dsw-alias-label-tertiary,#64748b);font-size:11px;text-transform:uppercase;letter-spacing:.06em}.url{margin-top:5px;border-radius:10px;padding:10px 12px;background:var(--dsw-alias-bg-layer-1,#f1f5f9);font:12px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace;overflow-wrap:anywhere}.actions{display:flex;align-items:center;gap:8px;margin-top:18px}.spacer{flex:1}button{min-height:36px;border:1px solid var(--dsw-alias-border-l2,#dbe1ea);border-radius:9px;padding:7px 13px;background:transparent;color:inherit;cursor:pointer;font:inherit;font-size:12px;font-weight:600;line-height:18px;transition:transform 100ms ease-out,background-color 120ms ease,color 120ms ease}button:hover:not(:disabled){background:var(--dsw-alias-interactive-bg-hover,#e9eef5)}button:active:not(:disabled){transform:scale(.97)}button:disabled{cursor:default;opacity:.5}.primary,.dsh-remote-primary{border-color:var(--dsw-alias-label-primary,#172033);background:var(--dsw-alias-label-primary,#172033);color:var(--dsw-alias-bg-layer-3,#fff)}button:focus-visible{outline:2px solid var(--dsw-alias-state-business-primary,#2563eb);outline-offset:2px}@media(max-width:620px){.chooser-routes{grid-template-columns:1fr}.dsh-remote-route-description{min-height:0}}@media(prefers-reduced-motion:reduce){.dsh-remote-route,button{transition:none}button:active:not(:disabled){transform:none}}
      </style>
      <div class="backdrop" role="presentation"><section class="dialog" role="dialog" aria-modal="true" aria-labelledby="dsh-remote-dialog-title" aria-describedby="dsh-remote-dialog-description"><h2 id="dsh-remote-dialog-title"></h2><p class="body" id="dsh-remote-dialog-description"></p><div class="chooser"><div class="chooser-routes"></div></div><div class="pairing" hidden><img class="qr" alt=""><p class="label"></p><div class="url"></div></div><div class="actions"><button class="back" hidden></button><span class="spacer"></span><button class="copy" hidden></button><button class="primary close"></button></div></section></div>
    `
    const routes = layerShadow.querySelector('.chooser-routes')
    const lan = createTransportRoute(LAN_TRANSPORT)
    lanRoute = lan.route
    lanDescription = lan.description
    lanActionButton = lan.actionButton
    lanPairButton = lan.pairButton
    const tailscale = createTransportRoute(TAILSCALE_TRANSPORT)
    tailscaleRoute = tailscale.route
    tailscaleDescription = tailscale.description
    tailscaleActionButton = tailscale.actionButton
    tailscalePairButton = tailscale.pairButton
    routes.append(lanRoute, tailscaleRoute)
    layerShadow.querySelector('.backdrop').addEventListener('click', event => {
      if (event.target === event.currentTarget) closePairing()
    })
    layerShadow.querySelector('.close').addEventListener('click', closePairing)
    layerShadow.querySelector('.copy').addEventListener('click', copyAddress)
    layerShadow.querySelector('.back').addEventListener('click', openConnectionManager)
    document.addEventListener('keydown', event => {
      if (event.key === 'Escape') {
        if (layer.hidden) return
        closePairing()
        return
      }
      if (event.key !== 'Tab' || layer.hidden) return
      const controls = [...layerShadow.querySelectorAll('button')]
        .filter(button => !button.disabled && !button.hidden && button.getClientRects().length > 0)
      if (!controls.length) return
      const first = controls[0]
      const last = controls[controls.length - 1]
      const active = layerShadow.activeElement
      if (!controls.includes(active)) {
        event.preventDefault()
        const target = event.shiftKey ? last : first
        target.focus()
      } else if (event.shiftKey && active === first) {
        event.preventDefault()
        last.focus()
      } else if (!event.shiftKey && active === last) {
        event.preventDefault()
        first.focus()
      }
    }, true)
    layer.hidden = true
    document.body.append(layer)
    updateSetting()
  }

  async function copyAddress() {
    const button = layerShadow?.querySelector('.copy')
    if (pairingTransport === LAN_TRANSPORT) return
    const pairingURL = status.pairingURL
    const endpoint = status.url
    if (!button || !endpoint) return
    try {
      await navigator.clipboard.writeText(pairingURL || endpoint)
      button.textContent = copyFor(currentLanguage()).copied
    } catch {
      const selection = window.getSelection()
      const range = document.createRange()
      range.selectNodeContents(layerShadow.querySelector('.url'))
      selection.removeAllRanges()
      selection.addRange(range)
    }
  }

  function openConnectionManager() {
    const shouldRememberFocus = !layer || layer.hidden
    ensureLayer()
    if (shouldRememberFocus) pairingReturnFocus = document.activeElement
    const copy = copyFor(currentLanguage())
    layerShadow.querySelector('h2').textContent = copy.connect
    layerShadow.querySelector('.body').textContent = copy.managerBody
    layerShadow.querySelector('.chooser').hidden = false
    layerShadow.querySelector('.pairing').hidden = true
    layerShadow.querySelector('.back').hidden = true
    layerShadow.querySelector('.copy').hidden = true
    layerShadow.querySelector('.close').textContent = copy.managerClose
    layer.hidden = false
    updateSetting()
    let preferredControl = layerShadow.querySelector('.close')
    if (status.lanEnabled && !lanPairButton.disabled && !lanPairButton.hidden) {
      preferredControl = lanPairButton
    } else if (!lanActionButton.disabled) {
      preferredControl = lanActionButton
    } else if (status.enabled && !tailscalePairButton.disabled && !tailscalePairButton.hidden) {
      preferredControl = tailscalePairButton
    } else if (!tailscaleActionButton.disabled) {
      preferredControl = tailscaleActionButton
    }
    preferredControl.focus()
  }

  function openPairing(transport = TAILSCALE_TRANSPORT) {
    const lan = transport === LAN_TRANSPORT
    const enabled = lan ? status.lanEnabled : status.enabled
    const qrSvg = lan ? status.lanQrSvg : status.qrSvg
    const endpoint = lan ? status.lanURL : status.url
    if (!enabled || !qrSvg) return
    const shouldRememberFocus = !layer || layer.hidden
    pairingTransport = transport
    ensureLayer()
    const copy = copyFor(currentLanguage())
    const title = lan ? copy.lanModalTitle : copy.modalTitle
    if (shouldRememberFocus) pairingReturnFocus = document.activeElement
    layerShadow.querySelector('h2').textContent = title
    layerShadow.querySelector('.body').textContent = lan ? copy.lanModalBody : copy.modalBody
    layerShadow.querySelector('.chooser').hidden = true
    layerShadow.querySelector('.pairing').hidden = false
    layerShadow.querySelector('.qr').src = qrSvg
    layerShadow.querySelector('.qr').alt = title
    layerShadow.querySelector('.label').textContent = copy.address
    layerShadow.querySelector('.url').textContent = endpoint
    layerShadow.querySelector('.copy').textContent = copy.copy
    layerShadow.querySelector('.copy').hidden = lan
    layerShadow.querySelector('.back').textContent = copy.back
    layerShadow.querySelector('.back').hidden = false
    layerShadow.querySelector('.close').textContent = copy.close
    layer.hidden = false
    layerShadow.querySelector('.close').focus()
  }

  function closePairing() {
    if (!layer || layer.hidden) return
    layer.hidden = true
    if (pairingReturnFocus?.isConnected) pairingReturnFocus.focus()
    pairingReturnFocus = null
  }

  function publish(next) {
    const wasEnabled = status.enabled
    const wasLanEnabled = status.lanEnabled
    finishStatusRequest()
    const nextStatus = normalizeStatus(next)
    const nextLanPending = pendingActionAfterStatus(pendingLanAction, nextStatus, LAN_TRANSPORT)
    const nextTailscalePending = pendingActionAfterStatus(
      pendingTailscaleAction,
      nextStatus,
      TAILSCALE_TRANSPORT,
    )
    if (!nextLanPending) clearPendingAction(LAN_TRANSPORT)
    else pendingLanAction = nextLanPending
    if (!nextTailscalePending) clearPendingAction(TAILSCALE_TRANSPORT)
    else pendingTailscaleAction = nextTailscalePending
    status = nextStatus
    updateSetting()
    if (!wasEnabled && status.enabled) openPairing()
    if (!wasLanEnabled && status.lanEnabled) openPairing(LAN_TRANSPORT)
    const pairingVisible = layer && !layer.hidden && !layerShadow.querySelector('.pairing').hidden
    if (pairingVisible && pairingTransport === TAILSCALE_TRANSPORT && !status.enabled) openConnectionManager()
    if (pairingVisible && pairingTransport === LAN_TRANSPORT && !status.lanEnabled) openConnectionManager()
  }

  function scheduleMount() {
    if (mountFrame) return
    mountFrame = requestAnimationFrame(() => {
      mountFrame = 0
      mountSetting()
    })
  }

  function handleMutations(mutations) {
    if (mutations.some(mutation => mutation.type === 'attributes' && mutation.attributeName === 'lang')) {
      updateSetting()
    }
    const slot = document.querySelector(SETTINGS_SLOT_SELECTOR)
    if (slot && (!settingRow?.isConnected || settingRow.parentElement !== slot)) scheduleMount()
  }

  function finishStatusRequest() {
    statusRequestInFlight = false
    if (statusRequestTimer) window.clearTimeout(statusRequestTimer)
    statusRequestTimer = 0
  }

  function refreshStatus(force = false) {
    const hasPendingAction = Boolean(pendingLanAction || pendingTailscaleAction)
    if (!shouldPollStatus(
      status,
      settingRow?.isConnected,
      document.visibilityState === 'visible',
      statusRequestInFlight || hasPendingAction,
    )) return
    statusRequestInFlight = true
    statusRequestTimer = window.setTimeout(finishStatusRequest, STATUS_REQUEST_TIMEOUT_MS)
    try {
      request('remote-status', force ? { force: '1' } : undefined)
    } catch (error) {
      finishStatusRequest()
      throw error
    }
  }

  function pollStatus() {
    refreshStatus()
  }

  function start() {
    installStyle()
    observer = new MutationObserver(handleMutations)
    observer.observe(document.documentElement, { subtree: true, childList: true, attributes: true, attributeFilter: ['lang'] })
    window.addEventListener('focus', () => refreshStatus(true))
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'visible') refreshStatus(true)
    })
    window.setInterval(pollStatus, STATUS_POLL_INTERVAL_MS)
    mountSetting()
    window.setTimeout(() => refreshStatus(true), 0)
  }

  window.addEventListener('dsh-desktop-event', event => {
    const detail = event.detail || {}
    if (detail.type === 'remote-status') publish(detail.payload)
    if (detail.type === 'remote-error') {
      const message = detail.payload?.message || 'Remote failed.'
      clearPendingAction(lastActionTransport)
      publish(statusAfterError(status, lastActionTransport, message))
    }
  })

  if (document.documentElement) start()
  else window.addEventListener('DOMContentLoaded', start, { once: true })
})()
