/**
 * First-party Desktop streaming polish.
 *
 * This script is embedded by the native shells and runs outside the DSH
 * profile/bundle system. It smooths append-only assistant text directly in the
 * WebView and leaves the DSH client-plugin/runtime graph untouched.
 */
(() => {
  'use strict'

  const BRIDGE_KEY = '__DSH_DESKTOP_SMOOTH_STREAM__'
  const TEST_FLAG = '__DSH_SMOOTH_STREAM_TEST__'
  const TEST_API = '__DSH_SMOOTH_STREAM_TEST_API__'
  const STYLE_ID = 'dsh-desktop-smooth-stream-style'
  const SETTING_ID = 'dsh-desktop-smooth-stream-setting'
  const FLOW_SELECTOR = '[data-chat-flow-kind="assistant-step"]'
  const SETTINGS_SLOT_SELECTOR = '[data-slot="settings.general.item"]'
  const BLOCK_SELECTOR = [
    'p',
    'pre',
    'blockquote',
    'ul',
    'ol',
    'table',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    '[data-variant="think"]',
  ].join(',')
  const ANIMATION_ID = 'dsh-desktop-smooth-enter'
  const ENTER_DURATION_MS = 380
  const FLOW_IDLE_MS = 280
  const MAX_REVEAL_PER_FRAME = 14
  const REVEAL_FRACTION = 0.26
  const INITIAL_ENABLED = '__DSH_SMOOTH_STREAM_ENABLED__'
  const ACTION_TOKEN = '__DSH_ACTION_TOKEN__'

  function normalizeEnabled(value, fallback = true) {
    if (typeof value === 'boolean') return value
    if (value === 'true' || value === '1') return true
    if (value === 'false' || value === '0') return false
    return fallback
  }

  function languageFromTag(tag) {
    return String(tag || '').toLowerCase().startsWith('zh') ? 'zh' : 'en'
  }

  function settingCopy(language) {
    return language === 'zh'
      ? {
          title: '平滑流式输出',
          description: '柔化新内容的出现，不延迟模型输出。',
          on: '开启',
          off: '关闭',
          error: '设置未能保存，请重试。',
        }
      : {
          title: 'Smooth streaming',
          description: 'Softens new content without delaying model output.',
          on: 'On',
          off: 'Off',
          error: 'The setting could not be saved. Try again.',
        }
  }

  function settingActionUrl(enabled, token = ACTION_TOKEN) {
    const query = new URLSearchParams({
      token,
      enabled: enabled ? '1' : '0',
    })
    return `dsh-desktop://action/set-smooth-stream?${query.toString()}`
  }

  function isAppendChange(previous, next) {
    return typeof previous === 'string'
      && typeof next === 'string'
      && next.length > previous.length
      && next.startsWith(previous)
  }

  function splitGraphemes(value) {
    const text = String(value || '')
    if (typeof Intl?.Segmenter === 'function') {
      const segmenter = new Intl.Segmenter(undefined, { granularity: 'grapheme' })
      return Array.from(segmenter.segment(text), entry => entry.segment)
    }
    return Array.from(text)
  }

  function revealBatchSize(backlog) {
    const pending = Math.max(0, Number(backlog) || 0)
    if (pending === 0) return 0
    return Math.min(MAX_REVEAL_PER_FRAME, Math.max(1, Math.ceil(pending * REVEAL_FRACTION)))
  }

  const testGlobal = typeof globalThis === 'undefined' ? null : globalThis
  if (testGlobal?.[TEST_FLAG] === true) {
    testGlobal[TEST_API] = Object.freeze({
      languageFromTag,
      normalizeEnabled,
      isAppendChange,
      revealBatchSize,
      settingActionUrl,
      settingCopy,
      splitGraphemes,
    })
    return
  }

  if (typeof window === 'undefined' || typeof document === 'undefined') return
  if (location.protocol !== 'http:' || location.hostname !== '127.0.0.1') return

  let snapshot = Object.freeze({
    enabled: normalizeEnabled(INITIAL_ENABLED, true),
    error: '',
    revision: 0,
  })
  const subscribers = new Set()
  const activeTextStates = new Set()
  const animatedBlocks = new WeakSet()
  const textStates = new WeakMap()
  const flowStates = new WeakMap()
  let observer = null
  let mountFrame = 0
  let revealFrame = 0
  let settingRow = null
  let settingText = null
  let settingDescription = null
  let settingButton = null
  let settingState = null

  const reducedMotion = typeof matchMedia === 'function'
    ? matchMedia('(prefers-reduced-motion: reduce)')
    : { matches: false }

  function publish(next) {
    snapshot = Object.freeze({
      ...snapshot,
      ...next,
      revision: snapshot.revision + 1,
    })
    applyEnabledState()
    updateSettingRow()
    for (const subscriber of [...subscribers]) {
      try { subscriber() } catch {}
    }
  }

  function requestEnabled(enabled) {
    const next = Boolean(enabled)
    publish({ enabled: next, error: '' })
    if (!ACTION_TOKEN.startsWith('__DSH_')) location.assign(settingActionUrl(next))
  }

  const bridge = Object.freeze({
    getSnapshot: () => snapshot,
    setEnabled: requestEnabled,
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
  window.dispatchEvent(new CustomEvent('dsh-desktop-smooth-stream-ready'))

  function installStyle() {
    if (document.getElementById(STYLE_ID)) return
    const style = document.createElement('style')
    style.id = STYLE_ID
    style.textContent = `
      #${SETTING_ID} {
        box-sizing: border-box;
        border-bottom: 1px solid var(--dsw-alias-border-l2);
        display: flex;
        align-items: center;
        gap: 16px;
        width: 100%;
        padding: 16px 0;
        color: var(--dsw-alias-label-primary);
        font: inherit;
      }
      #${SETTING_ID} .dsh-smooth-setting-copy {
        display: flex;
        flex: 1;
        min-width: 0;
        flex-direction: column;
        gap: 4px;
        padding-right: 32px;
      }
      #${SETTING_ID} .dsh-smooth-setting-title {
        color: var(--dsw-alias-label-primary);
        font-size: 14px;
        font-weight: 400;
        line-height: 22px;
      }
      #${SETTING_ID} .dsh-smooth-setting-description {
        color: var(--dsw-alias-label-tertiary);
        font-size: 12px;
        font-weight: 400;
        line-height: 18px;
      }
      #${SETTING_ID}[data-error] .dsh-smooth-setting-description {
        color: var(--dsw-alias-state-error-primary);
      }
      #${SETTING_ID} .dsh-smooth-setting-switch {
        box-sizing: border-box;
        border: 0;
        border-radius: 18px;
        display: inline-flex;
        flex: none;
        align-items: center;
        gap: 9px;
        height: 36px;
        padding: 0 12px 0 8px;
        background: var(--dsw-alias-bg-module-platform);
        color: var(--dsw-alias-label-secondary);
        cursor: pointer;
        font: inherit;
        font-size: 13px;
        line-height: 20px;
      }
      #${SETTING_ID} .dsh-smooth-setting-switch:hover {
        background: var(--dsw-alias-interactive-bg-hover);
      }
      #${SETTING_ID} .dsh-smooth-setting-switch:focus-visible {
        outline: 2px solid var(--dsw-alias-state-business-primary);
        outline-offset: 2px;
      }
      #${SETTING_ID} .dsh-smooth-setting-track {
        box-sizing: border-box;
        border-radius: 999px;
        display: inline-flex;
        align-items: center;
        width: 30px;
        height: 18px;
        padding: 2px;
        background: var(--dsw-alias-label-caption);
        transition: background-color 160ms ease;
      }
      #${SETTING_ID} .dsh-smooth-setting-knob {
        border-radius: 50%;
        width: 14px;
        height: 14px;
        background: var(--dsw-static-neutral-white, #fff);
        box-shadow: 0 1px 2px rgba(0, 0, 0, .2);
        transition: transform 180ms cubic-bezier(.22, 1, .36, 1);
      }
      #${SETTING_ID} .dsh-smooth-setting-switch[aria-checked="true"] {
        color: var(--dsw-alias-label-primary);
      }
      #${SETTING_ID} .dsh-smooth-setting-switch[aria-checked="true"] .dsh-smooth-setting-track {
        background: var(--dsw-alias-state-business-primary);
      }
      #${SETTING_ID} .dsh-smooth-setting-switch[aria-checked="true"] .dsh-smooth-setting-knob {
        transform: translateX(12px);
      }
      @media (prefers-reduced-motion: reduce) {
        #${SETTING_ID} .dsh-smooth-setting-track,
        #${SETTING_ID} .dsh-smooth-setting-knob {
          transition: none;
        }
      }
    `
    ;(document.head || document.documentElement).append(style)
  }

  function currentLanguage() {
    return languageFromTag(document.documentElement.lang || navigator.language)
  }

  function createSettingRow() {
    const row = document.createElement('div')
    row.id = SETTING_ID

    const copy = document.createElement('div')
    copy.className = 'dsh-smooth-setting-copy'
    settingText = document.createElement('div')
    settingText.className = 'dsh-smooth-setting-title'
    settingDescription = document.createElement('div')
    settingDescription.className = 'dsh-smooth-setting-description'
    copy.append(settingText, settingDescription)

    settingButton = document.createElement('button')
    settingButton.type = 'button'
    settingButton.className = 'dsh-smooth-setting-switch'
    settingButton.setAttribute('role', 'switch')
    settingButton.addEventListener('click', () => requestEnabled(!snapshot.enabled))

    const track = document.createElement('span')
    track.className = 'dsh-smooth-setting-track'
    track.setAttribute('aria-hidden', 'true')
    const knob = document.createElement('span')
    knob.className = 'dsh-smooth-setting-knob'
    track.append(knob)
    settingState = document.createElement('span')
    settingState.className = 'dsh-smooth-setting-state'
    settingButton.append(track, settingState)

    row.append(copy, settingButton)
    settingRow = row
    updateSettingRow()
    return row
  }

  function updateSettingRow() {
    if (!settingRow || !settingText || !settingDescription || !settingButton || !settingState) return
    const copy = settingCopy(currentLanguage())
    settingText.textContent = copy.title
    settingDescription.textContent = snapshot.error ? copy.error : copy.description
    settingState.textContent = snapshot.enabled ? copy.on : copy.off
    settingButton.setAttribute('aria-checked', String(snapshot.enabled))
    settingButton.setAttribute('aria-label', `${copy.title}: ${snapshot.enabled ? copy.on : copy.off}`)
    settingRow.toggleAttribute('data-error', Boolean(snapshot.error))
  }

  function mountSettingRow() {
    const slot = document.querySelector(SETTINGS_SLOT_SELECTOR)
    if (!slot) return
    if (settingRow?.isConnected && settingRow.parentElement === slot) {
      updateSettingRow()
      return
    }
    const existing = document.getElementById(SETTING_ID)
    if (existing) existing.remove()
    slot.append(createSettingRow())
  }

  function elementFromNode(node) {
    if (node?.nodeType === Node.ELEMENT_NODE) return node
    return node?.parentElement || null
  }

  function assistantFlowFrom(node) {
    const element = elementFromNode(node)
    if (!element) return null
    if (element.matches?.(FLOW_SELECTOR)) return element
    return element.closest?.(FLOW_SELECTOR) || null
  }

  function semanticBlockFrom(node, flow) {
    const element = elementFromNode(node)
    if (!element || !flow?.contains(element)) return null
    const block = element.matches?.(BLOCK_SELECTOR) ? element : element.closest?.(BLOCK_SELECTOR)
    return block && flow.contains(block) ? block : null
  }

  function blocksWithin(node) {
    const element = elementFromNode(node)
    if (!element) return []
    const blocks = []
    if (element.matches?.(BLOCK_SELECTOR)) blocks.push(element)
    if (element.querySelectorAll) blocks.push(...element.querySelectorAll(BLOCK_SELECTOR))
    return blocks
  }

  function flowState(flow) {
    let state = flowStates.get(flow)
    if (state) return state
    state = {
      lastActivity: 0,
      previousBlocks: new Set(),
    }
    flowStates.set(flow, state)
    return state
  }

  function blockSignature(block) {
    const text = String(block?.textContent || '').trim()
    return text ? `${block.tagName}:${text}` : ''
  }

  function rememberPreviousBlock(state, block) {
    const signature = blockSignature(block)
    if (!signature) return
    state.previousBlocks.add(signature)
    while (state.previousBlocks.size > 96) {
      state.previousBlocks.delete(state.previousBlocks.values().next().value)
    }
  }

  function touchFlow(flow) {
    flowState(flow).lastActivity = performance.now()
  }

  function cancelSmoothAnimations() {
    if (typeof document.getAnimations !== 'function') return
    for (const animation of document.getAnimations()) {
      if (animation.id === ANIMATION_ID) animation.cancel()
    }
  }

  function animateBlock(block) {
    if (!snapshot.enabled || reducedMotion.matches || typeof block?.animate !== 'function') return
    if (animatedBlocks.has(block)) return
    animatedBlocks.add(block)
    const animation = block.animate(
      [
        { opacity: .18, filter: 'blur(4px)', transform: 'translateY(6px)' },
        { opacity: 1, filter: 'blur(0)', transform: 'translateY(0)' },
      ],
      {
        duration: ENTER_DURATION_MS,
        easing: 'cubic-bezier(.22, 1, .36, 1)',
      },
    )
    try { animation.id = ANIMATION_ID } catch {}
  }

  function observeDocument() {
    observer?.observe(document.documentElement, {
      subtree: true,
      childList: true,
      characterData: true,
      characterDataOldValue: true,
      attributes: true,
      attributeFilter: ['lang'],
    })
  }

  function writeText(node, value) {
    if (!node?.isConnected || node.data === value) return
    observer?.disconnect()
    node.data = value
    observeDocument()
  }

  function scheduleReveal() {
    if (revealFrame || activeTextStates.size === 0) return
    revealFrame = requestAnimationFrame(revealTextFrame)
  }

  function revealTextFrame() {
    revealFrame = 0
    for (const state of [...activeTextStates]) {
      if (!state.node.isConnected || !state.target.startsWith(state.visible)) {
        activeTextStates.delete(state)
        textStates.delete(state.node)
        continue
      }
      const remaining = splitGraphemes(state.target.slice(state.visible.length))
      const count = revealBatchSize(remaining.length)
      if (count > 0) {
        state.visible += remaining.slice(0, count).join('')
        writeText(state.node, state.visible)
      }
      if (state.visible === state.target) activeTextStates.delete(state)
    }
    scheduleReveal()
  }

  function queueTextChange(node, previous, next) {
    if (!snapshot.enabled || reducedMotion.matches || !isAppendChange(previous, next)) return
    const flow = assistantFlowFrom(node)
    if (!flow) return

    let state = textStates.get(node)
    if (!state) {
      state = { node, flow, visible: previous, target: next }
      textStates.set(node, state)
    } else if (next.startsWith(state.visible)) {
      state.target = next
    } else {
      textStates.delete(node)
      activeTextStates.delete(state)
      return
    }

    const block = semanticBlockFrom(node, flow)
    if (block) animateBlock(block)
    touchFlow(flow)
    activeTextStates.add(state)
    writeText(node, state.visible)
    scheduleReveal()
  }

  function processChildMutation(mutation) {
    const flow = assistantFlowFrom(mutation.target)
      || [...mutation.addedNodes, ...mutation.removedNodes].map(assistantFlowFrom).find(Boolean)
    if (!flow) return
    const state = flowState(flow)
    for (const removed of mutation.removedNodes) {
      for (const block of blocksWithin(removed)) rememberPreviousBlock(state, block)
    }
    if (!snapshot.enabled || performance.now() - state.lastActivity > FLOW_IDLE_MS * 2) return
    for (const added of mutation.addedNodes) {
      for (const block of blocksWithin(added)) {
        if (!flow.contains(block)) continue
        const signature = blockSignature(block)
        if (signature && state.previousBlocks.has(signature)) continue
        animateBlock(block)
      }
    }
  }

  function handleMutations(mutations) {
    const textChanges = new Map()
    for (const mutation of mutations) {
      if (mutation.type === 'characterData') {
        const current = textChanges.get(mutation.target)
        if (current) current.next = mutation.target.data
        else textChanges.set(mutation.target, {
          previous: mutation.oldValue || '',
          next: mutation.target.data,
        })
      }
    }
    for (const [node, change] of textChanges) queueTextChange(node, change.previous, change.next)
    for (const mutation of mutations) {
      if (mutation.type === 'childList') processChildMutation(mutation)
    }
    scheduleMount()
  }

  function scheduleMount() {
    if (mountFrame) return
    mountFrame = requestAnimationFrame(() => {
      mountFrame = 0
      mountSettingRow()
    })
  }

  function flushText() {
    if (revealFrame) cancelAnimationFrame(revealFrame)
    revealFrame = 0
    for (const state of [...activeTextStates]) writeText(state.node, state.target)
    activeTextStates.clear()
  }

  function clearSmoothEffects() {
    flushText()
    cancelSmoothAnimations()
  }

  function applyEnabledState() {
    document.documentElement.setAttribute(
      'data-dsh-desktop-smooth-stream',
      snapshot.enabled ? 'on' : 'off',
    )
    if (!snapshot.enabled) clearSmoothEffects()
    scheduleMount()
  }

  function start() {
    installStyle()
    observer = new MutationObserver(handleMutations)
    observeDocument()
    applyEnabledState()
    mountSettingRow()
  }

  window.addEventListener('dsh-desktop-event', event => {
    const detail = event.detail || {}
    const payload = detail.payload || {}
    if (detail.type === 'smooth-stream-setting') {
      publish({ enabled: normalizeEnabled(payload.enabled, snapshot.enabled), error: '' })
    } else if (detail.type === 'smooth-stream-setting-error') {
      publish({
        enabled: normalizeEnabled(payload.enabled, snapshot.enabled),
        error: payload.message || 'save-failed',
      })
    }
  })

  if (document.documentElement) start()
  else window.addEventListener('DOMContentLoaded', start, { once: true })
})()
