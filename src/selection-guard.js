/**
 * Desktop text-selection boundary.
 *
 * Harness is also a browser application, where selectable navigation labels
 * are harmless. In a desktop window they make ordinary drags and Cmd/Ctrl+A
 * look like a broken native UI. Keep application chrome inert while leaving
 * authored conversation content, code, logs, and editors copyable.
 */
(() => {
  'use strict'

  const STYLE_ID = 'dsh-desktop-selection-guard'

  if (typeof window === 'undefined' || typeof document === 'undefined') return
  if (location.protocol !== 'http:' || location.hostname !== '127.0.0.1') return

  function install() {
    if (!document.head || document.getElementById(STYLE_ID)) return
    const style = document.createElement('style')
    style.id = STYLE_ID
    style.textContent = `
      html body, html body * {
        -webkit-user-select: none !important;
        user-select: none !important;
      }
      html body :is(
        input,
        textarea,
        [contenteditable="true"],
        [contenteditable="plaintext-only"],
        [data-chat-flow-kind],
        [data-chat-flow-kind] *,
        pre,
        pre *,
        code,
        code *
      ) {
        -webkit-user-select: text !important;
        user-select: text !important;
      }
      html body :is(
        button,
        [role="button"],
        [role="tree"],
        [role="treeitem"],
        [role="tab"],
        [role="tablist"],
        [role="menu"],
        [role="menuitem"],
        [role="menuitemradio"]
      ) {
        -webkit-user-select: none !important;
        user-select: none !important;
      }
    `
    document.head.append(style)
  }

  if (document.head) install()
  else window.addEventListener('DOMContentLoaded', install, { once: true })
})()
