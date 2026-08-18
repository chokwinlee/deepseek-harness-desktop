/**
 * First-party Tailscale Remote controls for the native Desktop shell.
 *
 * The Web UI can request status or an explicit enable/disable transition, but
 * it never receives shell access or Tailscale credentials. The native host
 * validates every action and owns both Harness and Serve child processes.
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
  const ALLOWED_ACTIONS = new Set(['remote-status', 'remote-open-https', 'remote-enable', 'remote-disable'])

  function languageFromTag(tag) {
    return String(tag || '').toLowerCase().startsWith('zh') ? 'zh' : 'en'
  }

  function actionUrl(action, token = ACTION_TOKEN) {
    if (!ALLOWED_ACTIONS.has(action)) throw new Error(`Unsupported Remote action: ${action}`)
    const query = new URLSearchParams({ token })
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
    })
  }

  function copyFor(language) {
    return language === 'zh'
      ? {
          title: '手机 Remote',
          description: '通过你自己的 Tailscale 网络从 iPhone 安全控制这台电脑。',
          unavailable: '请先安装 Tailscale，并让电脑和 iPhone 登录同一个 Tailnet。',
          disconnected: 'Tailscale 尚未连接。',
          magicDNS: '当前 Tailnet 需要开启 MagicDNS。',
          https: '请先在 Tailscale 管理页启用 HTTPS。',
          setupHTTPS: '设置 HTTPS',
          active: '仅在你的 Tailnet 内可访问：{url}',
          enable: '开启',
          enabling: '正在开启…',
          disable: '关闭',
          disabling: '正在关闭…',
          pair: '配对',
          modalTitle: '连接 iPhone',
          modalBody: '在 DSH Remote 中扫描二维码。手机和电脑必须登录同一个 Tailnet。',
          address: 'Remote 地址',
          copy: '复制地址',
          copied: '已复制',
          close: '完成',
          restart: '开启或关闭 Remote 会安全重启 Harness，正在运行的任务会中断。',
        }
      : {
          title: 'Mobile Remote',
          description: 'Control this computer from iPhone through your own Tailscale network.',
          unavailable: 'Install Tailscale and sign in to the same tailnet on this computer and iPhone.',
          disconnected: 'Tailscale is not connected.',
          magicDNS: 'MagicDNS must be enabled for this tailnet.',
          https: 'Enable HTTPS in the Tailscale admin console first.',
          setupHTTPS: 'Set up HTTPS',
          active: 'Available only inside your tailnet: {url}',
          enable: 'Enable',
          enabling: 'Enabling…',
          disable: 'Turn off',
          disabling: 'Turning off…',
          pair: 'Pair',
          modalTitle: 'Connect iPhone',
          modalBody: 'Scan this QR code in DSH Remote. Both devices must use the same tailnet.',
          address: 'Remote address',
          copy: 'Copy address',
          copied: 'Copied',
          close: 'Done',
          restart: 'Enabling or disabling Remote safely restarts Harness and interrupts running tasks.',
        }
  }

  const testGlobal = typeof globalThis === 'undefined' ? null : globalThis
  if (testGlobal?.[TEST_FLAG] === true) {
    testGlobal[TEST_API] = Object.freeze({ actionUrl, copyFor, languageFromTag, normalizeStatus })
    return
  }

  if (typeof window === 'undefined' || typeof document === 'undefined') return
  if (location.protocol !== 'http:' || location.hostname !== '127.0.0.1') return

  let status = normalizeStatus()
  let settingRow = null
  let settingTitle = null
  let settingDescription = null
  let settingControls = null
  let settingPrimaryButton = null
  let settingPairButton = null
  let layer = null
  let layerShadow = null
  let observer = null
  let mountFrame = 0

  function currentLanguage() {
    return languageFromTag(document.documentElement.lang || navigator.language)
  }

  function request(action) {
    location.assign(actionUrl(action))
  }

  function installStyle() {
    if (document.getElementById(STYLE_ID)) return
    const style = document.createElement('style')
    style.id = STYLE_ID
    style.textContent = `
      #${SETTING_ID}{box-sizing:border-box;border-bottom:1px solid var(--dsw-alias-border-l2);display:flex;align-items:center;gap:16px;width:100%;padding:16px 0;color:var(--dsw-alias-label-primary);font:inherit}
      #${SETTING_ID} *{box-sizing:border-box}
      #${SETTING_ID} .dsh-remote-copy{display:flex;flex:1;min-width:0;flex-direction:column;gap:4px;padding-right:24px}
      #${SETTING_ID} .dsh-remote-title{color:var(--dsw-alias-label-primary);font-size:14px;font-weight:400;line-height:22px}
      #${SETTING_ID} .dsh-remote-description{color:var(--dsw-alias-label-tertiary);font-size:12px;font-weight:400;line-height:18px;overflow-wrap:anywhere}
      #${SETTING_ID}[data-error] .dsh-remote-description{color:var(--dsw-alias-state-error-primary)}
      #${SETTING_ID} .dsh-remote-controls{display:flex;flex:none;align-items:center;gap:7px}
      #${SETTING_ID} button{box-sizing:border-box;border:1px solid var(--dsw-alias-border-l2);border-radius:9px;min-height:34px;padding:6px 11px;background:transparent;color:var(--dsw-alias-label-secondary);cursor:pointer;font:inherit;font-size:12px;font-weight:600;line-height:18px;white-space:nowrap}
      #${SETTING_ID} button:hover:not(:disabled){background:var(--dsw-alias-interactive-bg-hover);color:var(--dsw-alias-label-primary)}
      #${SETTING_ID} button:focus-visible{outline:2px solid var(--dsw-alias-state-business-primary);outline-offset:2px}
      #${SETTING_ID} button:disabled{cursor:default;opacity:.5}
      #${SETTING_ID} .dsh-remote-primary{border-color:var(--dsw-alias-label-primary);background:var(--dsw-alias-label-primary);color:var(--dsw-alias-bg-layer-3)}
      @media(max-width:620px){#${SETTING_ID}{align-items:flex-start;flex-direction:column}#${SETTING_ID} .dsh-remote-copy{padding-right:0}#${SETTING_ID} .dsh-remote-controls{width:100%;justify-content:flex-end}}
    `
    ;(document.head || document.documentElement).append(style)
  }

  function description(copy) {
    if (status.error) return status.error
    if (!status.installed) return copy.unavailable
    if (status.backendState !== 'Running') return copy.disconnected
    if (!status.magicDNS) return copy.magicDNS
    if (!status.httpsReady) return copy.https
    if (status.enabled) return copy.active.replace('{url}', status.url)
    return `${copy.description} ${copy.restart}`
  }

  function canEnable() {
    return status.installed
      && status.backendState === 'Running'
      && status.magicDNS
      && status.httpsReady
      && !status.busy
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

  function renderControls(copy) {
    if (!settingPrimaryButton || !settingPairButton) return
    if (status.enabled) {
      configureButton(settingPrimaryButton, copy.disable, '', status.busy)
      configureButton(settingPairButton, copy.pair, 'dsh-remote-primary', status.busy)
      return
    }
    configureButton(settingPairButton, copy.pair, 'dsh-remote-primary', true, true)
    if (status.installed
      && status.backendState === 'Running'
      && status.magicDNS
      && !status.httpsReady
      && !status.busy) {
      configureButton(settingPrimaryButton, copy.setupHTTPS, 'dsh-remote-primary', false)
      return
    }
    const label = status.busy
      ? status.phase === 'stopping' ? copy.disabling : copy.enabling
      : copy.enable
    configureButton(settingPrimaryButton, label, 'dsh-remote-primary', !canEnable())
  }

  function updateSetting() {
    if (!settingRow || !settingTitle || !settingDescription) return
    const copy = copyFor(currentLanguage())
    settingTitle.textContent = copy.title
    settingDescription.textContent = description(copy)
    settingRow.toggleAttribute('data-error', Boolean(status.error))
    renderControls(copy)
  }

  function createSettingRow() {
    const row = document.createElement('div')
    row.id = SETTING_ID
    const content = document.createElement('div')
    content.className = 'dsh-remote-copy'
    settingTitle = document.createElement('div')
    settingTitle.className = 'dsh-remote-title'
    settingDescription = document.createElement('div')
    settingDescription.className = 'dsh-remote-description'
    content.append(settingTitle, settingDescription)
    settingControls = document.createElement('div')
    settingControls.className = 'dsh-remote-controls'
    settingPrimaryButton = createButton('', 'dsh-remote-primary', () => {
      if (status.enabled) request('remote-disable')
      else if (status.installed
        && status.backendState === 'Running'
        && status.magicDNS
        && !status.httpsReady) request('remote-open-https')
      else request('remote-enable')
    })
    settingPairButton = createButton('', 'dsh-remote-primary', openPairing, true)
    settingControls.append(settingPrimaryButton, settingPairButton)
    row.append(content, settingControls)
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
        :host{all:initial}:host([hidden]){display:none}*{box-sizing:border-box}.backdrop{position:fixed;z-index:2147483002;inset:0;display:grid;place-items:center;padding:24px;background:rgba(9,16,29,.48);font:13px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}.dialog{width:min(460px,100%);border:1px solid var(--dsw-alias-border-l2,#dbe1ea);border-radius:18px;padding:22px;background:var(--dsw-alias-bg-layer-3,#fff);color:var(--dsw-alias-label-primary,#111827);box-shadow:0 24px 80px rgba(0,0,0,.28)}h2,p{margin:0}h2{font-size:19px;line-height:26px}.body{margin-top:6px;color:var(--dsw-alias-label-tertiary,#64748b)}.qr{display:block;width:248px;height:248px;margin:20px auto 16px;border:10px solid #fff;border-radius:14px;background:#fff}.label{margin-top:6px;color:var(--dsw-alias-label-tertiary,#64748b);font-size:11px;text-transform:uppercase;letter-spacing:.06em}.url{margin-top:5px;border-radius:10px;padding:10px 12px;background:var(--dsw-alias-bg-layer-1,#f1f5f9);font:12px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace;overflow-wrap:anywhere}.actions{display:flex;justify-content:flex-end;gap:8px;margin-top:18px}button{min-height:36px;border:1px solid var(--dsw-alias-border-l2,#dbe1ea);border-radius:9px;padding:7px 13px;background:transparent;color:inherit;cursor:pointer;font:inherit;font-size:12px;font-weight:600;line-height:18px}.primary{border-color:var(--dsw-alias-label-primary,#172033);background:var(--dsw-alias-label-primary,#172033);color:var(--dsw-alias-bg-layer-3,#fff)}button:focus-visible{outline:2px solid var(--dsw-alias-state-business-primary,#2563eb);outline-offset:2px}
      </style>
      <div class="backdrop" role="presentation"><section class="dialog" role="dialog" aria-modal="true" aria-labelledby="dsh-remote-dialog-title"><h2 id="dsh-remote-dialog-title"></h2><p class="body"></p><img class="qr" alt=""><p class="label"></p><div class="url"></div><div class="actions"><button class="copy"></button><button class="primary close"></button></div></section></div>
    `
    layerShadow.querySelector('.backdrop').addEventListener('click', event => {
      if (event.target === event.currentTarget) closePairing()
    })
    layerShadow.querySelector('.close').addEventListener('click', closePairing)
    layerShadow.querySelector('.copy').addEventListener('click', copyAddress)
    document.body.append(layer)
  }

  async function copyAddress() {
    const button = layerShadow?.querySelector('.copy')
    if (!button || !status.url) return
    try {
      await navigator.clipboard.writeText(status.url)
      button.textContent = copyFor(currentLanguage()).copied
    } catch {
      const selection = window.getSelection()
      const range = document.createRange()
      range.selectNodeContents(layerShadow.querySelector('.url'))
      selection.removeAllRanges()
      selection.addRange(range)
    }
  }

  function openPairing() {
    if (!status.enabled || !status.qrSvg) return
    ensureLayer()
    const copy = copyFor(currentLanguage())
    layerShadow.querySelector('h2').textContent = copy.modalTitle
    layerShadow.querySelector('.body').textContent = copy.modalBody
    layerShadow.querySelector('.qr').src = status.qrSvg
    layerShadow.querySelector('.qr').alt = copy.modalTitle
    layerShadow.querySelector('.label').textContent = copy.address
    layerShadow.querySelector('.url').textContent = status.url
    layerShadow.querySelector('.copy').textContent = copy.copy
    layerShadow.querySelector('.close').textContent = copy.close
    layer.hidden = false
    layerShadow.querySelector('.close').focus()
  }

  function closePairing() {
    if (layer) layer.hidden = true
  }

  function publish(next) {
    const wasEnabled = status.enabled
    status = normalizeStatus(next)
    updateSetting()
    if (!wasEnabled && status.enabled) openPairing()
    if (!status.enabled) closePairing()
  }

  function scheduleMount() {
    if (mountFrame) return
    mountFrame = requestAnimationFrame(() => {
      mountFrame = 0
      mountSetting()
    })
  }

  function refreshStatus() {
    if (document.visibilityState === 'visible') request('remote-status')
  }

  function start() {
    installStyle()
    observer = new MutationObserver(scheduleMount)
    observer.observe(document.documentElement, { subtree: true, childList: true, attributes: true, attributeFilter: ['lang'] })
    window.addEventListener('focus', refreshStatus)
    document.addEventListener('visibilitychange', refreshStatus)
    mountSetting()
    window.setTimeout(refreshStatus, 0)
  }

  window.addEventListener('dsh-desktop-event', event => {
    const detail = event.detail || {}
    if (detail.type === 'remote-status') publish(detail.payload)
    if (detail.type === 'remote-error') {
      publish({ ...status, busy: false, phase: 'error', error: detail.payload?.message || 'Remote failed.' })
    }
  })

  if (document.documentElement) start()
  else window.addEventListener('DOMContentLoaded', start, { once: true })
})()
