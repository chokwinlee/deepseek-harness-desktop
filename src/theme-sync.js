/**
 * Keeps the native desktop chrome aligned with the theme rendered by Harness.
 * Harness owns the palette; the desktop shell only mirrors its resolved color
 * scheme and base background into the native window.
 */
(() => {
  'use strict'

  const ACTION_TOKEN = '__DSH_ACTION_TOKEN__'
  const DARK_ATTRIBUTE = 'data-ds-dark-theme'
  const SYNC_ACTION = 'sync-theme'

  function parseRgbChannels(raw) {
    const match = String(raw || '').match(
      /^rgba?\(\s*(\d+(?:\.\d+)?)\s*[, ]\s*(\d+(?:\.\d+)?)\s*[, ]\s*(\d+(?:\.\d+)?)/i,
    )
    if (!match) return null
    const channels = match.slice(1, 4).map(value => Math.round(Number(value)))
    if (channels.some(value => !Number.isFinite(value) || value < 0 || value > 255)) return null
    return channels
  }

  const testGlobal = typeof globalThis === 'undefined' ? null : globalThis
  if (testGlobal?.__DSH_THEME_SYNC_TEST__ === true) {
    testGlobal.__DSH_THEME_SYNC_TEST_API__ = Object.freeze({ parseRgbChannels })
  }

  if (typeof window === 'undefined' || typeof document === 'undefined') return

  const trustedHarness = location.protocol === 'http:' && location.hostname === '127.0.0.1'
  const trustedRecovery = location.protocol === 'tauri:' || location.hostname === 'tauri.localhost'
  if (!trustedHarness && !trustedRecovery) return

  let lastSignature = ''
  let syncTimer = 0

  function resolvedScheme() {
    const inline = document.documentElement.style.colorScheme
    if (inline === 'light' || inline === 'dark') return inline
    if (document.body?.hasAttribute(DARK_ATTRIBUTE)) return 'dark'
    return matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'
  }

  function resolvedBackground() {
    if (!document.body) return null
    const probe = document.createElement('span')
    probe.setAttribute('aria-hidden', 'true')
    probe.style.cssText = [
      'position:fixed',
      'width:0',
      'height:0',
      'pointer-events:none',
      'background:var(--dsw-alias-bg-base,transparent)',
    ].join(';')
    document.body.append(probe)
    const themed = parseRgbChannels(getComputedStyle(probe).backgroundColor)
    probe.remove()
    if (themed) return themed
    return parseRgbChannels(getComputedStyle(document.documentElement).backgroundColor)
      || parseRgbChannels(getComputedStyle(document.body).backgroundColor)
  }

  function syncNativeTheme() {
    syncTimer = 0
    const scheme = resolvedScheme()
    const color = resolvedBackground()
    const signature = `${scheme}:${color?.join(',') || ''}`
    if (signature === lastSignature) return
    lastSignature = signature

    const query = new URLSearchParams({ token: ACTION_TOKEN, scheme })
    if (color) {
      query.set('red', String(color[0]))
      query.set('green', String(color[1]))
      query.set('blue', String(color[2]))
    }
    location.assign(`dsh-desktop://action/${SYNC_ACTION}?${query.toString()}`)
  }

  function scheduleSync() {
    if (syncTimer) window.clearTimeout(syncTimer)
    syncTimer = window.setTimeout(syncNativeTheme, 0)
  }

  function startThemeSync() {
    if (!document.body) return
    const observer = new MutationObserver(scheduleSync)
    observer.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ['style'],
    })
    observer.observe(document.body, {
      attributes: true,
      attributeFilter: ['style', DARK_ATTRIBUTE],
    })
    matchMedia('(prefers-color-scheme: dark)').addEventListener('change', scheduleSync)
    scheduleSync()
  }

  // Custom-protocol navigation before WKWebView completes the HTTP request can
  // cancel the initial Harness page load, so begin mirroring only after load.
  if (document.readyState === 'complete') startThemeSync()
  else window.addEventListener('load', startThemeSync, { once: true })
})()
