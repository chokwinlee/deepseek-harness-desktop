/**
 * DeepSeek Harness Desktop update checker.
 *
 * Injected by the Tauri and Electron shells into the Harness Web UI. The
 * desktop-only version row is mounted immediately before Harness Settings so it
 * participates in the sidebar layout instead of covering upstream controls.
 */
(() => {
  'use strict'

  const CURRENT_VERSION = '__DSH_CURRENT_VERSION__'
  const REPO = 'chokwinlee/deepseek-harness-desktop'
  const API_URL = 'https://api.github.com/repos/' + REPO + '/releases/latest'
  const RELEASE_PAGE = 'https://github.com/' + REPO + '/releases/latest'
  const IGNORE_KEY = 'dshDesktopIgnoredVersion'
  const CHECK_DELAY_MS = 4000
  const RECHECK_INTERVAL_MS = 6 * 60 * 60 * 1000
  const MAX_NOTES_CHARS = 420

  const COPY = Object.freeze({
    zh: Object.freeze({
      checkUpdates: '检查更新',
      checking: '正在检查更新…',
      checkFailed: '检查更新失败',
      networkError: '无法连接 GitHub Releases，请检查网络后重试。',
      rateLimited: 'GitHub 暂时限制了更新检查，请稍后重试。',
      retry: '重试',
      close: '关闭',
      currentTitle: '已是最新版本',
      currentBadge: '最新',
      currentBody: '没有发现新版本。',
      currentVersion: '当前版本',
      latestVersion: '最新版本',
      updateTitle: '发现新版本',
      releaseNotesFallback: '暂无发布说明。',
      download: '下载更新',
      ignore: '忽略此版本',
      ignoredTitle: '已忽略',
      ignoredBody: '该版本不会再提醒。',
      restore: '恢复提醒',
      published: '发布于',
    }),
    en: Object.freeze({
      checkUpdates: 'Check for updates',
      checking: 'Checking for updates…',
      checkFailed: 'Could not check for updates',
      networkError: 'Could not reach GitHub Releases. Check your connection and try again.',
      rateLimited: 'GitHub temporarily limited update checks. Try again later.',
      retry: 'Retry',
      close: 'Close',
      currentTitle: 'You’re up to date',
      currentBadge: 'Current',
      currentBody: 'No newer version was found.',
      currentVersion: 'Current version',
      latestVersion: 'Latest version',
      updateTitle: 'Update available',
      releaseNotesFallback: 'No release notes were provided.',
      download: 'Download update',
      ignore: 'Ignore this version',
      ignoredTitle: 'Ignored',
      ignoredBody: 'You will not be reminded about this version again.',
      restore: 'Restore reminder',
      published: 'Released',
    }),
  })

  function parseVersion(raw) {
    const source = String(raw || '').trim().replace(/^v/i, '')
    const match = /^(\d+)\.(\d+)\.(\d+)/.exec(source)
    if (!match) return null
    return match.slice(1).map(Number)
  }

  function isNewer(latest, current) {
    const candidate = parseVersion(latest)
    const installed = parseVersion(current)
    if (!candidate || !installed) return false
    for (let index = 0; index < 3; index += 1) {
      if (candidate[index] > installed[index]) return true
      if (candidate[index] < installed[index]) return false
    }
    return false
  }

  function versionLabel(raw) {
    const version = parseVersion(raw)
    return version ? 'v' + version.join('.') : String(raw || '')
  }

  function statusForRelease(tag, current, ignored) {
    if (!isNewer(tag, current)) return 'current'
    return ignored && ignored === tag ? 'ignored' : 'update'
  }

  function shouldShowForStatus(status) {
    return status === 'update'
  }

  function summarize(body, fallback = '') {
    if (!body) return fallback
    let text = String(body)
      .replace(/<!--[\s\S]*?-->/g, '')
      .replace(/^#+\s*/gm, '')
      .replace(/\*\*/g, '')
      .replace(/[\x60]/g, '')
      .replace(/\[([^\]]*)\]\([^)]*\)/g, '$1')
      .trim()
    if (text.length > MAX_NOTES_CHARS) text = text.slice(0, MAX_NOTES_CHARS) + '…'
    return text || fallback
  }

  function resolveLocaleFromHints(hints, languages) {
    const text = (hints || []).filter(Boolean).join(' ')
    if (/\b(settings|new session|workspaces)\b/i.test(text)) return 'en'
    if (/(设置|新会话|工作区)/.test(text)) return 'zh'
    for (const tag of languages || []) {
      const primary = String(tag || '').toLowerCase().split('-')[0]
      if (primary === 'en' || primary === 'zh') return primary
    }
    return 'zh'
  }

  function copyFor(locale) {
    return COPY[locale] || COPY.zh
  }

  function friendlyError(error, locale) {
    const copy = copyFor(locale)
    const message = error instanceof Error ? error.message : String(error || '')
    if (/HTTP 403|HTTP 429/.test(message)) return copy.rateLimited
    return copy.networkError
  }

  const testGlobal = typeof globalThis === 'undefined' ? null : globalThis
  if (testGlobal && testGlobal.__DSH_UPDATER_TEST__ === true) {
    testGlobal.__DSH_UPDATER_TEST_API__ = Object.freeze({
      copyFor,
      isNewer,
      parseVersion,
      resolveLocaleFromHints,
      shouldShowForStatus,
      statusForRelease,
      summarize,
      versionLabel,
    })
  }

  if (typeof window === 'undefined' || typeof document === 'undefined') return
  if (window.__dshUpdaterInstalled) return
  window.__dshUpdaterInstalled = true

  function readIgnored() {
    try { return localStorage.getItem(IGNORE_KEY) || null } catch { return null }
  }

  function writeIgnored(value) {
    try {
      if (value) localStorage.setItem(IGNORE_KEY, value)
      else localStorage.removeItem(IGNORE_KEY)
    } catch { /* storage is optional */ }
  }

  const state = {
    status: 'checking',
    latest: null,
    error: null,
    panelOpen: false,
    locale: resolveLocaleFromHints([], [...navigator.languages || [], navigator.language]),
    layout: 'wide',
  }

  let host = null
  let shadow = null
  let rootEl = null
  let triggerEl = null
  let versionEl = null
  let panelEl = null
  let titleEl = null
  let bodyEl = null
  let notesEl = null
  let actionsEl = null
  let primaryEl = null
  let secondaryEl = null
  let closeEl = null
  let liveEl = null
  let settingsTrigger = null
  let triggerObserver = null
  let triggerResizeObserver = null
  let railPositionTimer = null

  const STYLES = [
    ':host { display: block; flex: none; width: 100%; min-width: 0; }',
    ':host([hidden]) { display: none; }',
    ':host([data-layout="rail"]) {',
    '  position: fixed;',
    '  z-index: 900;',
    '  left: var(--dshu-host-left, 14px);',
    '  top: var(--dshu-host-top, auto);',
    '  width: 36px;',
    '  height: 36px;',
    '}',
    '.dshu-root {',
    '  position: relative;',
    '  color: var(--dsw-alias-label-primary, oklch(0.24 0.01 255));',
    '  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;',
    '  font-size: 13px;',
    '  line-height: 1.45;',
    '}',
    '.dshu-trigger {',
    '  box-sizing: border-box;',
    '  position: relative;',
    '  cursor: pointer;',
    '  height: 34px;',
    '  color: var(--dsw-alias-label-primary, oklch(0.24 0.01 255));',
    '  background: var(--dsw-alias-button-elevated-fill, oklch(0.94 0.006 255));',
    '  border: 0;',
    '  border-radius: 12px;',
    '  display: flex;',
    '  align-items: center;',
    '  gap: 10px;',
    '  padding: 5px 7px 5px 10px;',
    '  font: inherit;',
    '  line-height: 22px;',
    '  transition: background-color 140ms cubic-bezier(0.22, 1, 0.36, 1);',
    '}',
    '.dshu-root[data-layout="wide"] .dshu-trigger { width: calc(100% + 8px); margin: 0 -4px 4px; }',
    '.dshu-root[data-layout="rail"] .dshu-trigger {',
    '  width: 36px;',
    '  height: 36px;',
    '  justify-content: center;',
    '  gap: 0;',
    '  padding: 0;',
    '  margin: 0 0 2px;',
    '  border-radius: 50%;',
    '}',
    '.dshu-trigger:hover { background: var(--dsw-alias-interactive-bg-hover, oklch(0.92 0.006 255)); }',
    '.dshu-trigger:focus-visible, .dshu-close:focus-visible, .dshu-action:focus-visible {',
    '  outline: 2px solid var(--dsw-alias-state-business-primary, oklch(0.62 0.17 260));',
    '  outline-offset: 2px;',
    '}',
    '.dshu-icon {',
    '  width: 22px;',
    '  height: 22px;',
    '  flex: none;',
    '  display: grid;',
    '  place-items: center;',
    '  padding: 5px;',
    '  box-sizing: border-box;',
    '  border-radius: 50%;',
    '  color: oklch(0.98 0.004 255);',
    '  background: var(--dsw-alias-state-business-primary, oklch(0.62 0.17 260));',
    '}',
    '.dshu-icon svg, .dshu-close svg { width: 100%; height: 100%; display: block; }',
    '.dshu-version { flex: 1; min-width: 0; overflow: hidden; text-align: left; text-overflow: ellipsis; white-space: nowrap; }',
    '.dshu-root[data-layout="rail"] .dshu-version { display: none; }',
    '.dshu-panel {',
    '  box-sizing: border-box;',
    '  position: fixed;',
    '  left: var(--dshu-panel-left, 14px);',
    '  bottom: var(--dshu-panel-bottom, 58px);',
    '  z-index: 900;',
    '  width: min(320px, calc(100vw - 28px));',
    '  max-height: min(360px, calc(100vh - 80px));',
    '  overflow: hidden;',
    '  border: 1px solid var(--dsw-alias-border-l2, oklch(0.86 0.008 255));',
    '  border-radius: 16px;',
    '  padding: 14px;',
    '  background: var(--dsw-alias-bg-layer-2, oklch(0.98 0.004 255));',
    '  color: var(--dsw-alias-label-primary, oklch(0.24 0.01 255));',
    '  box-shadow: var(--dsw-shadow-lv3, 0 12px 36px oklch(0.18 0.01 255 / 0.2));',
    '  outline: none;',
    '}',
    '.dshu-panel[hidden] { display: none; }',
    '.dshu-header { display: flex; align-items: flex-start; gap: 10px; margin-bottom: 8px; }',
    '.dshu-title { min-width: 0; flex: 1; display: flex; align-items: center; flex-wrap: wrap; gap: 6px; font-size: 14px; font-weight: 600; line-height: 20px; }',
    '.dshu-badge {',
    '  padding: 1px 7px;',
    '  border-radius: 999px;',
    '  background: color-mix(in oklch, var(--dsw-static-green-500, oklch(0.72 0.19 150)) 16%, transparent);',
    '  color: var(--dsw-static-green-500, oklch(0.66 0.18 150));',
    '  font-size: 11px;',
    '  font-weight: 600;',
    '  line-height: 18px;',
    '}',
    '.dshu-close {',
    '  width: 28px;',
    '  height: 28px;',
    '  flex: none;',
    '  display: grid;',
    '  place-items: center;',
    '  padding: 7px;',
    '  color: var(--dsw-alias-label-secondary, oklch(0.48 0.01 255));',
    '  background: transparent;',
    '  border: 0;',
    '  border-radius: 50%;',
    '  cursor: pointer;',
    '}',
    '.dshu-close:hover { background: var(--dsw-alias-interactive-bg-hover, oklch(0.92 0.006 255)); }',
    '.dshu-versions { color: var(--dsw-alias-label-secondary, oklch(0.48 0.01 255)); font-size: 12px; line-height: 18px; }',
    '.dshu-versions b { color: var(--dsw-alias-label-primary, oklch(0.24 0.01 255)); font-weight: 600; }',
    '.dshu-notes {',
    '  max-height: 132px;',
    '  margin-top: 10px;',
    '  overflow-y: auto;',
    '  color: var(--dsw-alias-label-secondary, oklch(0.48 0.01 255));',
    '  background: var(--dsw-alias-bg-layer-3, oklch(0.95 0.005 255));',
    '  border-radius: 10px;',
    '  padding: 9px 10px;',
    '  font-size: 12px;',
    '  line-height: 18px;',
    '  white-space: pre-wrap;',
    '  overflow-wrap: anywhere;',
    '}',
    '.dshu-notes[hidden], .dshu-actions[hidden] { display: none; }',
    '.dshu-actions { display: flex; justify-content: flex-end; gap: 8px; margin-top: 12px; }',
    '.dshu-action {',
    '  min-height: 32px;',
    '  padding: 5px 12px;',
    '  border: 1px solid transparent;',
    '  border-radius: 10px;',
    '  cursor: pointer;',
    '  font: inherit;',
    '  font-size: 12.5px;',
    '  font-weight: 500;',
    '  transition: background-color 140ms cubic-bezier(0.22, 1, 0.36, 1);',
    '}',
    '.dshu-primary { color: var(--dsw-alias-label-primary-inverted, oklch(0.98 0.004 255)); background: var(--dsw-alias-button-primary-fill, oklch(0.62 0.17 260)); }',
    '.dshu-primary:hover { background: var(--dsw-alias-button-primary-hover, oklch(0.57 0.18 260)); }',
    '.dshu-secondary { color: var(--dsw-alias-label-primary, oklch(0.24 0.01 255)); background: var(--dsw-alias-button-elevated-fill, oklch(0.94 0.006 255)); border-color: var(--dsw-alias-border-l2, oklch(0.86 0.008 255)); }',
    '.dshu-secondary:hover { background: var(--dsw-alias-interactive-bg-hover, oklch(0.91 0.007 255)); }',
    '.dshu-live { position: fixed; width: 1px; height: 1px; overflow: hidden; clip: rect(0 0 0 0); white-space: nowrap; }',
    '@media (prefers-reduced-motion: reduce) {',
    '  .dshu-trigger, .dshu-action { transition: none; }',
    '}',
  ].join('\n')

  function downloadIcon() {
    return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 3v11"/><path d="m8 10 4 4 4-4"/><path d="M5 20h14"/></svg>'
  }

  function closeIcon() {
    return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg>'
  }

  function buildUI() {
    host = document.createElement('div')
    host.id = 'dsh-desktop-updater'
    host.hidden = true
    host.dataset.layout = state.layout
    shadow = host.attachShadow({ mode: 'open' })

    const style = document.createElement('style')
    style.textContent = STYLES
    shadow.appendChild(style)

    rootEl = document.createElement('div')
    rootEl.className = 'dshu-root'
    rootEl.dataset.layout = state.layout
    rootEl.innerHTML =
      '<button class="dshu-trigger" type="button" aria-haspopup="dialog" aria-expanded="false" aria-controls="dshu-update-panel">' +
        '<span class="dshu-version"></span>' +
        '<span class="dshu-icon">' + downloadIcon() + '</span>' +
      '</button>' +
      '<section class="dshu-panel" id="dshu-update-panel" role="dialog" aria-labelledby="dshu-update-title" tabindex="-1" hidden>' +
        '<div class="dshu-header">' +
          '<div class="dshu-title" id="dshu-update-title"></div>' +
          '<button class="dshu-close" type="button">' + closeIcon() + '</button>' +
        '</div>' +
        '<div class="dshu-versions"></div>' +
        '<div class="dshu-notes"></div>' +
        '<div class="dshu-actions">' +
          '<button class="dshu-action dshu-secondary" type="button" data-action="secondary"></button>' +
          '<button class="dshu-action dshu-primary" type="button" data-action="primary"></button>' +
        '</div>' +
      '</section>' +
      '<div class="dshu-live" role="status" aria-live="polite" aria-atomic="true"></div>'
    shadow.appendChild(rootEl)

    triggerEl = rootEl.querySelector('.dshu-trigger')
    versionEl = rootEl.querySelector('.dshu-version')
    panelEl = rootEl.querySelector('.dshu-panel')
    titleEl = rootEl.querySelector('.dshu-title')
    bodyEl = rootEl.querySelector('.dshu-versions')
    notesEl = rootEl.querySelector('.dshu-notes')
    actionsEl = rootEl.querySelector('.dshu-actions')
    primaryEl = rootEl.querySelector('[data-action="primary"]')
    secondaryEl = rootEl.querySelector('[data-action="secondary"]')
    closeEl = rootEl.querySelector('.dshu-close')
    liveEl = rootEl.querySelector('.dshu-live')

    triggerEl.addEventListener('click', (event) => {
      event.stopPropagation()
      if (state.panelOpen) closePanel(true)
      else openPanel()
    })
    closeEl.addEventListener('click', (event) => {
      event.stopPropagation()
      closePanel(true)
    })
    primaryEl.addEventListener('click', (event) => {
      event.stopPropagation()
      onPrimary()
    })
    secondaryEl.addEventListener('click', (event) => {
      event.stopPropagation()
      onSecondary()
    })
    document.addEventListener('click', (event) => {
      if (!state.panelOpen) return
      const path = event.composedPath ? event.composedPath() : []
      if (!path.includes(host)) closePanel(false)
    })
    document.addEventListener('keydown', (event) => {
      if (event.key === 'Escape' && state.panelOpen) {
        event.stopPropagation()
        closePanel(true)
      }
    })
    window.addEventListener('resize', updateShellContext)

    return host
  }

  function findSettingsTrigger() {
    const candidates = document.querySelectorAll('button[aria-haspopup="dialog"]')
    for (const candidate of candidates) {
      if (candidate === triggerEl) continue
      if (candidate.hasAttribute('aria-expanded')) return candidate
    }
    return null
  }

  function inferLocale() {
    const hints = []
    if (settingsTrigger) {
      hints.push(settingsTrigger.textContent, settingsTrigger.getAttribute('aria-label'), settingsTrigger.title)
    }
    const labelledButtons = document.querySelectorAll('button[aria-label], button[title]')
    for (let index = 0; index < Math.min(labelledButtons.length, 24); index += 1) {
      const button = labelledButtons[index]
      if (button === triggerEl) continue
      hints.push(button.getAttribute('aria-label'), button.title)
    }
    return resolveLocaleFromHints(hints, [...navigator.languages || [], navigator.language])
  }

  function observeTrigger(nextTrigger) {
    triggerObserver?.disconnect()
    triggerResizeObserver?.disconnect()
    settingsTrigger = nextTrigger

    triggerObserver = new MutationObserver(updateShellContext)
    triggerObserver.observe(nextTrigger, {
      attributes: true,
      attributeFilter: ['aria-label', 'class', 'title'],
      characterData: true,
      childList: true,
      subtree: true,
    })
    if (typeof ResizeObserver !== 'undefined') {
      triggerResizeObserver = new ResizeObserver(updateShellContext)
      triggerResizeObserver.observe(nextTrigger)
    }
  }

  function mountNextToSettings() {
    const nextTrigger = findSettingsTrigger()
    if (!nextTrigger || !nextTrigger.parentNode) {
      host.hidden = true
      return false
    }
    if (settingsTrigger !== nextTrigger) observeTrigger(nextTrigger)
    if (host.parentNode !== nextTrigger.parentNode || host.nextSibling !== nextTrigger) {
      nextTrigger.parentNode.insertBefore(host, nextTrigger)
    }
    updateShellContext()
    syncVisibility()
    return true
  }

  function updateShellContext() {
    if (!settingsTrigger?.isConnected) {
      mountNextToSettings()
      return
    }
    const rect = settingsTrigger.getBoundingClientRect()
    const nextLayout = rect.width > 80 || Boolean(settingsTrigger.textContent?.trim()) ? 'wide' : 'rail'
    const nextLocale = inferLocale()
    const changed = nextLayout !== state.layout || nextLocale !== state.locale
    state.layout = nextLayout
    state.locale = nextLocale
    host.dataset.layout = state.layout
    rootEl.dataset.layout = state.layout
    if (state.layout === 'rail') {
      positionRailHost()
      window.requestAnimationFrame(positionRailHost)
      window.clearTimeout(railPositionTimer)
      railPositionTimer = window.setTimeout(positionRailHost, 260)
    } else {
      window.clearTimeout(railPositionTimer)
      host.style.removeProperty('--dshu-host-left')
      host.style.removeProperty('--dshu-host-top')
    }
    if (changed) {
      renderBadge(false)
      if (state.panelOpen) renderPanel()
    }
    if (state.panelOpen) positionPanel()
  }

  function positionRailHost() {
    if (state.layout !== 'rail' || !settingsTrigger?.isConnected) return
    const rect = settingsTrigger.getBoundingClientRect()
    host.style.setProperty('--dshu-host-left', rect.left + 'px')
    host.style.setProperty('--dshu-host-top', Math.max(8, rect.top - 40) + 'px')
    if (state.panelOpen) positionPanel()
  }

  function positionPanel() {
    if (!triggerEl || !panelEl) return
    const rect = triggerEl.getBoundingClientRect()
    const panelWidth = Math.min(320, Math.max(0, window.innerWidth - 28))
    const left = Math.max(14, Math.min(rect.left, window.innerWidth - panelWidth - 14))
    const bottom = Math.max(14, window.innerHeight - rect.top + 8)
    rootEl.style.setProperty('--dshu-panel-left', left + 'px')
    rootEl.style.setProperty('--dshu-panel-bottom', bottom + 'px')
  }

  function openPanel() {
    state.panelOpen = true
    renderPanel()
    panelEl.hidden = false
    triggerEl.setAttribute('aria-expanded', 'true')
    positionPanel()
    window.requestAnimationFrame(() => {
      try { panelEl.focus({ preventScroll: true }) } catch { panelEl.focus() }
    })
  }

  function closePanel(restoreFocus) {
    state.panelOpen = false
    panelEl.hidden = true
    triggerEl.setAttribute('aria-expanded', 'false')
    if (restoreFocus) triggerEl.focus()
  }

  function appendBadge(label) {
    const badge = document.createElement('span')
    badge.className = 'dshu-badge'
    badge.textContent = label
    titleEl.appendChild(badge)
  }

  function renderPanel() {
    const copy = copyFor(state.locale)
    const latest = state.latest || {}
    const latestTag = versionLabel(latest.tag_name)

    titleEl.textContent = ''
    bodyEl.textContent = ''
    notesEl.textContent = ''
    notesEl.hidden = true
    actionsEl.hidden = true
    primaryEl.textContent = ''
    secondaryEl.textContent = ''
    closeEl.setAttribute('aria-label', copy.close)

    if (state.status === 'checking') {
      titleEl.textContent = copy.checking
      bodyEl.textContent = copy.currentVersion + ' ' + versionLabel(CURRENT_VERSION)
      return
    }

    if (state.status === 'error') {
      titleEl.textContent = copy.checkFailed
      bodyEl.textContent = friendlyError(state.error, state.locale)
      actionsEl.hidden = false
      primaryEl.textContent = copy.retry
      secondaryEl.textContent = copy.close
      return
    }

    if (state.status === 'current') {
      titleEl.textContent = copy.currentTitle
      appendBadge(copy.currentBadge)
      bodyEl.innerHTML = copy.currentVersion + ' <b>' + versionLabel(CURRENT_VERSION) + '</b>'
      notesEl.textContent = copy.currentBody
      notesEl.hidden = false
      return
    }

    if (state.status === 'ignored') {
      titleEl.textContent = copy.ignoredTitle + ' ' + latestTag
      bodyEl.innerHTML = copy.currentVersion + ' <b>' + versionLabel(CURRENT_VERSION) + '</b>'
      notesEl.textContent = copy.ignoredBody
      notesEl.hidden = false
      actionsEl.hidden = false
      secondaryEl.textContent = copy.restore
      primaryEl.textContent = copy.download
      return
    }

    titleEl.textContent = copy.updateTitle
    appendBadge(latestTag)
    bodyEl.innerHTML =
      copy.currentVersion + ' <b>' + versionLabel(CURRENT_VERSION) + '</b> · ' +
      copy.latestVersion + ' <b>' + latestTag + '</b>' +
      (latest.published_at ? ' · ' + copy.published + ' ' + new Date(latest.published_at).toLocaleDateString(state.locale) : '')
    notesEl.textContent = summarize(latest.body, copy.releaseNotesFallback)
    notesEl.hidden = false
    actionsEl.hidden = false
    secondaryEl.textContent = copy.ignore
    primaryEl.textContent = copy.download
  }

  function badgeLabel() {
    const copy = copyFor(state.locale)
    if (state.status === 'update') return copy.updateTitle + ' ' + versionLabel(state.latest?.tag_name)
    if (state.status === 'error') return copy.checkFailed
    if (state.status === 'checking') return copy.checking
    if (state.status === 'ignored') return copy.ignoredTitle + ' ' + versionLabel(state.latest?.tag_name)
    return copy.currentTitle + ' ' + versionLabel(CURRENT_VERSION)
  }

  function syncVisibility() {
    const shouldShow = shouldShowForStatus(state.status) && Boolean(settingsTrigger?.isConnected)
    host.hidden = !shouldShow
    if (!shouldShow && state.panelOpen) closePanel(false)
  }

  function renderBadge(announce) {
    if (!triggerEl) return
    const label = badgeLabel()
    triggerEl.dataset.status = state.status
    triggerEl.setAttribute('aria-label', label)
    triggerEl.title = label
    versionEl.textContent = state.status === 'update' ? label : ''
    syncVisibility()
    if (announce && state.status === 'update') liveEl.textContent = label
  }

  function openRelease() {
    const url = state.latest?.html_url || RELEASE_PAGE
    window.location.href = url
  }

  function onPrimary() {
    if (state.status === 'error') {
      check()
      return
    }
    if (state.status === 'update' || state.status === 'ignored') openRelease()
  }

  function onSecondary() {
    if (state.status === 'error') {
      closePanel(true)
      return
    }
    if (state.status === 'ignored') {
      writeIgnored(null)
      check()
      return
    }
    if (state.status === 'update' && state.latest) {
      writeIgnored(state.latest.tag_name || '')
      state.status = 'ignored'
      renderBadge(true)
    }
  }

  async function check() {
    state.status = 'checking'
    state.error = null
    renderBadge(false)
    if (state.panelOpen) renderPanel()
    try {
      const response = await fetch(API_URL, {
        headers: { Accept: 'application/vnd.github+json' },
        cache: 'no-store',
      })
      if (!response.ok) throw new Error('HTTP ' + response.status)
      const release = await response.json()
      state.latest = release
      state.status = statusForRelease(release.tag_name || '', CURRENT_VERSION, readIgnored())
    } catch (error) {
      state.status = 'error'
      state.error = error
    }
    renderBadge(true)
    if (state.panelOpen) renderPanel()
  }

  function boot() {
    const element = buildUI()
    const bodyObserver = new MutationObserver(() => {
      if (!settingsTrigger?.isConnected) mountNextToSettings()
    })
    bodyObserver.observe(document.body, { childList: true, subtree: true })
    mountNextToSettings()
    renderBadge(false)
    window.setTimeout(check, CHECK_DELAY_MS)
    window.setInterval(() => {
      if (state.status !== 'checking') check()
    }, RECHECK_INTERVAL_MS)
    return element
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot, { once: true })
  } else {
    boot()
  }
})()
