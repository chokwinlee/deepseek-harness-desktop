/**
 * DeepSeek Harness Desktop — update checker.
 *
 * Injected by the Tauri (macOS) and Electron (Windows) shells into the harness
 * webview right after the document starts loading. It renders a small button in
 * the bottom-left corner (like Codex's version widget), queries the GitHub
 * releases API for this repository, and lets the user decide whether to
 * download the new version.
 *
 * Deliberately dependency-free and self-contained:
 *  - styles live in a closed Shadow DOM, so the host UI is never affected;
 *  - the "download update" action navigates to the release page, which the
 *    shell's navigation guard routes to the system browser;
 *  - the "dismiss this version" choice is remembered in localStorage so a
 *    session reload does not nag again.
 *
 * The build replaces __DSH_CURRENT_VERSION__ with the shell's own version.
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

  if (typeof window === 'undefined') return
  if (window.__dshUpdaterInstalled) return
  window.__dshUpdaterInstalled = true

  /* ---- semver helpers ---- */
  function parseVersion(raw) {
    const s = String(raw || '').trim().replace(/^v/i, '')
    const m = /^(\d+)\.(\d+)\.(\d+)/.exec(s)
    if (!m) return null
    return m.slice(1).map(Number)
  }
  function isNewer(latest, current) {
    const a = parseVersion(latest)
    const b = parseVersion(current)
    if (!a || !b) return false
    for (let i = 0; i < 3; i++) {
      if (a[i] > b[i]) return true
      if (a[i] < b[i]) return false
    }
    return false
  }
  function versionLabel(raw) {
    const v = parseVersion(raw)
    return v ? 'v' + v.join('.') : String(raw || '')
  }

  /* ---- tiny storage (may be unavailable, e.g. private mode) ---- */
  function readIgnored() {
    try { return localStorage.getItem(IGNORE_KEY) || null } catch { return null }
  }
  function writeIgnored(value) {
    try {
      if (value) localStorage.setItem(IGNORE_KEY, value)
      else localStorage.removeItem(IGNORE_KEY)
    } catch { /* ignore */ }
  }

  /* ---- state ---- */
  const state = {
    status: 'checking', // checking | update | current | ignored | error
    latest: null,
    error: null,
    panelOpen: false,
  }

  /* ---- UI ---- */
  let host = null
  let shadow = null
  let btnEl = null
  let panelEl = null
  let titleEl = null
  let bodyEl = null
  let notesEl = null
  let primaryEl = null
  let secondaryEl = null

  const STYLES = [
    ':host { all: initial; }',
    '.dshu-root {',
    '  position: fixed;',
    '  left: 14px;',
    '  bottom: 14px;',
    '  z-index: 2147483000;',
    '  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;',
    '  font-size: 13px;',
    '  line-height: 1.45;',
    '  -webkit-user-select: none;',
    '  user-select: none;',
    '}',
    '.dshu-btn {',
    '  display: grid;',
    '  place-items: center;',
    '  width: 34px;',
    '  height: 34px;',
    '  border-radius: 50%;',
    '  border: 1px solid transparent;',
    '  cursor: pointer;',
    '  padding: 0;',
    '  color: #f3f4f6;',
    '  background: rgba(38, 46, 58, 0.82);',
    '  box-shadow: 0 2px 10px rgba(0, 0, 0, 0.28);',
    '  transition: background 120ms ease, transform 120ms ease, border-color 120ms ease;',
    '  -webkit-backdrop-filter: blur(6px);',
    '  backdrop-filter: blur(6px);',
    '}',
    '.dshu-btn:hover { background: rgba(48, 58, 74, 0.94); transform: scale(1.05); }',
    '.dshu-btn:active { transform: scale(0.96); }',
    '.dshu-btn[data-status="update"] { border-color: rgba(52, 211, 153, 0.55); }',
    '.dshu-btn[data-status="error"] { border-color: rgba(251, 191, 36, 0.5); }',
    '.dshu-icon { width: 16px; height: 16px; display: grid; place-items: center; }',
    '.dshu-icon svg { width: 100%; height: 100%; display: block; }',
    '.dshu-dot {',
    '  position: absolute;',
    '  top: -1px;',
    '  right: -1px;',
    '  width: 9px;',
    '  height: 9px;',
    '  border-radius: 50%;',
    '  background: #34d399;',
    '  border: 2px solid rgba(20, 24, 31, 0.9);',
    '  display: none;',
    '}',
    '.dshu-btn[data-status="update"] .dshu-dot { display: block; animation: dshu-pulse 1.8s ease-in-out infinite; }',
    '.dshu-btn[data-status="checking"] .dshu-icon { animation: dshu-spin 900ms linear infinite; }',
    '@keyframes dshu-spin { to { transform: rotate(360deg); } }',
    '@keyframes dshu-pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.35; } }',
    '.dshu-panel {',
    '  position: absolute;',
    '  left: 0;',
    '  bottom: 44px;',
    '  width: 312px;',
    '  max-width: calc(100vw - 40px);',
    '  border-radius: 12px;',
    '  padding: 14px 16px;',
    '  background: rgba(24, 29, 38, 0.96);',
    '  color: #e5e7eb;',
    '  box-shadow: 0 12px 40px rgba(0, 0, 0, 0.45);',
    '  border: 1px solid rgba(255, 255, 255, 0.08);',
    '  -webkit-backdrop-filter: blur(14px);',
    '  backdrop-filter: blur(14px);',
    '  display: none;',
    '}',
    '.dshu-panel[open] { display: block; }',
    '.dshu-title { font-weight: 650; font-size: 13.5px; margin-bottom: 6px; display: flex; align-items: center; gap: 6px; }',
    '.dshu-title .dshu-badge { font-size: 11px; font-weight: 600; padding: 1px 7px; border-radius: 999px; background: rgba(52, 211, 153, 0.16); color: #34d399; }',
    '.dshu-versions { font-size: 12px; color: #9ca3af; margin-bottom: 8px; }',
    '.dshu-versions b { color: #e5e7eb; font-weight: 600; }',
    '.dshu-notes {',
    '  font-size: 12px;',
    '  color: #b6bdc9;',
    '  background: rgba(255, 255, 255, 0.045);',
    '  border-radius: 8px;',
    '  padding: 8px 10px;',
    '  margin-bottom: 12px;',
    '  max-height: 132px;',
    '  overflow-y: auto;',
    '  white-space: pre-wrap;',
    '  word-break: break-word;',
    '}',
    '.dshu-actions { display: flex; gap: 8px; justify-content: flex-end; }',
    '.dshu-btn2 { font: inherit; font-size: 12.5px; font-weight: 600; border-radius: 8px; border: 1px solid transparent; padding: 6px 12px; cursor: pointer; transition: filter 120ms ease, background 120ms ease; }',
    '.dshu-btn2:hover { filter: brightness(1.1); }',
    '.dshu-btn2:active { transform: scale(0.97); }',
    '.dshu-primary { background: #2563eb; color: #fff; }',
    '.dshu-secondary { background: rgba(255, 255, 255, 0.07); color: #cbd5e1; border-color: rgba(255,255,255,0.12); }',
    '.dshu-error { color: #fbbf24; }',
  ].join('\n')

  function svgIcon() {
    return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 5v14"/><path d="m6 13 6-6 6 6"/></svg>'
  }

  function buildUI() {
    host = document.createElement('div')
    host.id = 'dsh-desktop-updater'
    shadow = host.attachShadow({ mode: 'open' })

    const style = document.createElement('style')
    style.textContent = STYLES
    shadow.appendChild(style)

    const root = document.createElement('div')
    root.className = 'dshu-root'
    root.innerHTML =
      '<button class="dshu-btn" type="button" title="检查更新" aria-label="检查更新">' +
        '<span class="dshu-icon">' + svgIcon() + '</span>' +
        '<span class="dshu-dot"></span>' +
      '</button>' +
      '<div class="dshu-panel" role="dialog" aria-label="更新">' +
        '<div class="dshu-title"></div>' +
        '<div class="dshu-versions"></div>' +
        '<div class="dshu-notes"></div>' +
        '<div class="dshu-actions">' +
          '<button class="dshu-btn2 dshu-secondary" type="button" data-action="dismiss"></button>' +
          '<button class="dshu-btn2 dshu-primary" type="button" data-action="primary"></button>' +
        '</div>' +
      '</div>'
    shadow.appendChild(root)

    btnEl = root.querySelector('.dshu-btn')
    panelEl = root.querySelector('.dshu-panel')
    titleEl = root.querySelector('.dshu-title')
    bodyEl = root.querySelector('.dshu-versions')
    notesEl = root.querySelector('.dshu-notes')
    const actions = root.querySelector('.dshu-actions')
    primaryEl = actions.querySelector('[data-action="primary"]')
    secondaryEl = actions.querySelector('[data-action="dismiss"]')

    btnEl.addEventListener('click', (event) => {
      event.stopPropagation()
      togglePanel()
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
      if (!path.includes(host)) closePanel()
    })
    document.addEventListener('keydown', (event) => {
      if (event.key === 'Escape' && state.panelOpen) closePanel()
    })

    applyTheme()
    return host
  }

  function applyTheme() {
    if (!shadow) return
    const dark = document.body && document.body.hasAttribute('data-ds-dark-theme')
    if (dark === null || dark === undefined) return
    const root = shadow.querySelector('.dshu-root')
    if (root) root.dataset.theme = dark ? 'dark' : 'light'
  }

  function togglePanel() {
    if (state.panelOpen) closePanel()
    else openPanel()
  }
  function openPanel() {
    state.panelOpen = true
    renderPanel()
    panelEl.setAttribute('open', '')
  }
  function closePanel() {
    state.panelOpen = false
    panelEl.removeAttribute('open')
  }

  function renderPanel() {
    const s = state
    titleEl.innerHTML = ''
    notesEl.textContent = ''
    secondaryEl.textContent = '暂不更新'
    primaryEl.textContent = '下载更新'

    if (s.status === 'checking') {
      titleEl.textContent = '正在检查更新…'
      bodyEl.textContent = '当前版本 ' + versionLabel(CURRENT_VERSION)
      notesEl.textContent = ''
      secondaryEl.style.display = 'none'
      primaryEl.style.display = 'none'
      return
    }
    if (s.status === 'error') {
      titleEl.textContent = '检查更新失败'
      bodyEl.innerHTML = '<span class="dshu-error">' + escapeHtml(String(s.error || '网络错误')) + '</span>'
      notesEl.textContent = ''
      secondaryEl.textContent = '关闭'
      primaryEl.textContent = '重试'
      secondaryEl.style.display = ''
      primaryEl.style.display = ''
      return
    }
    if (s.status === 'current') {
      titleEl.textContent = '已是最新版本'
      const badge = document.createElement('span')
      badge.className = 'dshu-badge'
      badge.textContent = '最新'
      titleEl.appendChild(badge)
      bodyEl.innerHTML = '当前版本 <b>' + versionLabel(CURRENT_VERSION) + '</b>'
      notesEl.textContent = '没有发现新版本。'
      secondaryEl.style.display = 'none'
      primaryEl.style.display = 'none'
      return
    }
    if (s.status === 'ignored') {
      const tag = s.latest ? versionLabel(s.latest.tag_name) : ''
      titleEl.textContent = '已忽略 ' + tag
      bodyEl.innerHTML = '当前版本 <b>' + versionLabel(CURRENT_VERSION) + '</b>'
      notesEl.textContent = '该版本不会再提醒。'
      secondaryEl.textContent = '恢复提醒'
      primaryEl.textContent = '去下载'
      secondaryEl.style.display = ''
      primaryEl.style.display = ''
      return
    }
    // update
    const latest = s.latest || {}
    const tag = latest.tag_name || ''
    titleEl.textContent = '发现新版本'
    const badge = document.createElement('span')
    badge.className = 'dshu-badge'
    badge.textContent = versionLabel(tag)
    titleEl.appendChild(badge)
    bodyEl.innerHTML =
      '当前 <b>' + versionLabel(CURRENT_VERSION) + '</b> → 最新 <b>' + versionLabel(tag) + '</b>' +
      (latest.published_at ? ' · ' + new Date(latest.published_at).toLocaleDateString() : '')
    notesEl.textContent = summarize(latest.body)
    secondaryEl.style.display = ''
    primaryEl.style.display = ''
  }

  function summarize(body) {
    if (!body) return '（发布说明略）'
    let text = String(body)
      .replace(/<!--[\s\S]*?-->/g, '')
      .replace(/^#+\s*/gm, '')
      .replace(/\*\*/g, '')
      .replace(/[\x60]/g, '')
      .replace(/\[([^\]]*)\]\([^)]*\)/g, '$1')
      .trim()
    if (text.length > MAX_NOTES_CHARS) text = text.slice(0, MAX_NOTES_CHARS) + '…'
    return text
  }

  function escapeHtml(value) {
    return String(value).replace(/[&<>"']/g, (c) => ({
      '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
    }[c]))
  }

  /* ---- actions ---- */
  function onPrimary() {
    const s = state
    if (s.status === 'error') { closePanel(); check(); return }
    if (s.status === 'ignored') {
      writeIgnored(null)
      closePanel()
      check()
      return
    }
    if (s.status === 'update' && s.latest) {
      const url = s.latest.html_url || RELEASE_PAGE
      // The shell navigation guard catches this external navigation and
      // opens the system browser; the webview itself stays put.
      window.location.href = url
      return
    }
    closePanel()
  }

  function onSecondary() {
    const s = state
    if (s.status === 'error') { closePanel(); return }
    if (s.status === 'ignored') {
      writeIgnored(null)
      check()
      return
    }
    if (s.status === 'update' && s.latest) {
      writeIgnored(s.latest.tag_name || '')
      state.status = 'ignored'
      renderBadge()
    }
    closePanel()
  }

  /* ---- checking ---- */
  async function check() {
    state.status = 'checking'
    state.error = null
    renderBadge()
    try {
      const response = await fetch(API_URL, {
        headers: { Accept: 'application/vnd.github+json' },
        cache: 'no-store',
      })
      if (!response.ok) throw new Error('HTTP ' + response.status)
      const release = await response.json()
      state.latest = release
      const tag = release.tag_name || ''
      const ignored = readIgnored()
      if (ignored && ignored === tag) state.status = 'ignored'
      else if (isNewer(tag, CURRENT_VERSION)) state.status = 'update'
      else state.status = 'current'
    } catch (error) {
      state.status = 'error'
      state.error = error instanceof Error ? error.message : String(error)
    }
    renderBadge()
    if (state.panelOpen) renderPanel()
  }

  function renderBadge() {
    if (!btnEl) return
    btnEl.dataset.status = state.status
    const title =
      state.status === 'update' ? '发现新版本 ' + versionLabel(state.latest && state.latest.tag_name)
      : state.status === 'error' ? '检查更新失败'
      : state.status === 'checking' ? '正在检查更新…'
      : state.status === 'ignored' ? '已忽略更新'
      : '已是最新版本 ' + versionLabel(CURRENT_VERSION)
    btnEl.setAttribute('title', title)
    btnEl.setAttribute('aria-label', title)
  }

  /* ---- boot ---- */
  function boot() {
    const el = buildUI()
    document.body.appendChild(el)
    // theme changes (the host toggles data-ds-dark-theme on <body>)
    const observer = new MutationObserver(() => applyTheme())
    observer.observe(document.body, { attributes: true, attributeFilter: ['data-ds-dark-theme'] })
    renderBadge()
    window.setTimeout(check, CHECK_DELAY_MS)
    window.setInterval(() => {
      if (state.status !== 'checking') check()
    }, RECHECK_INTERVAL_MS)
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot, { once: true })
  } else {
    boot()
  }
})()
