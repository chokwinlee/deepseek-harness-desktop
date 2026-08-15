const errorNode = document.querySelector('#startup-error')
const noteNode = document.querySelector('#recovery-note')
const actionStatus = document.querySelector('#action-status')
const restoreAction = document.querySelector('#restore-action')
const safeModeAction = document.querySelector('#safe-mode-action')
const retryAction = document.querySelector('#retry-action')
const copyError = document.querySelector('#copy-error')
const actions = [restoreAction, safeModeAction, retryAction]

function resolveInvoke() {
  return window.__TAURI__?.core?.invoke || window.__TAURI_INTERNALS__?.invoke
}

function describeError(error) {
  if (typeof error === 'string') return error
  if (error instanceof Error) return error.message
  return String(error || '恢复操作未能完成。')
}

function setBusy(active, message = '') {
  document.body.toggleAttribute('data-busy', active)
  for (const button of actions) button.disabled = active
  actionStatus.hidden = !message
  actionStatus.textContent = message
}

function renderStatus(status) {
  const error = typeof status?.error === 'string' && status.error
    ? status.error
    : 'DeepSeek Harness exited before reporting a local URL.'
  errorNode.textContent = error

  if (status?.snapshotAvailable) {
    restoreAction.hidden = false
    safeModeAction.classList.remove('primary')
    safeModeAction.classList.add('secondary')
    if (status.detectedPlugin) {
      restoreAction.textContent = `撤销 ${status.detectedPlugin} 并重新加载`
      noteNode.textContent = `检测到 ${status.detectedPlugin} 加载失败。将恢复此前验证过的插件 profile；会话、凭据和设置保持不变。`
    } else {
      restoreAction.textContent = '恢复上次可用状态'
      noteNode.textContent = '将恢复此前验证过的插件 profile；会话、凭据和设置保持不变。'
    }
  } else {
    restoreAction.hidden = true
    safeModeAction.classList.remove('secondary')
    safeModeAction.classList.add('primary')
    noteNode.textContent = status?.detectedPlugin
      ? `检测到 ${status.detectedPlugin} 加载失败。当前还没有可用快照，可以先临时跳过第三方 bundle 启动。`
      : '当前还没有可用快照。安全模式会临时跳过第三方 bundle，原 profile 不会被修改。'
  }
  setBusy(Boolean(status?.busy), status?.busy ? '正在执行恢复操作，请稍候…' : '')
}

async function loadStatus() {
  const invoke = resolveInvoke()
  if (typeof invoke !== 'function') {
    renderStatus({
      error: window.__DSH_STARTUP_ERROR__,
      snapshotAvailable: false,
      detectedPlugin: null,
      busy: false,
    })
    return
  }
  try {
    renderStatus(await invoke('recovery_status'))
  } catch (error) {
    renderStatus({ error: describeError(error), snapshotAvailable: false, busy: false })
  }
}

async function runAction(command, message) {
  const invoke = resolveInvoke()
  if (typeof invoke !== 'function') {
    setBusy(false, '当前恢复页面无法连接桌面宿主，请重新打开应用。')
    return
  }
  setBusy(true, message)
  try {
    await invoke(command)
    await loadStatus()
  } catch (error) {
    setBusy(false, describeError(error))
    await loadStatus()
  }
}

restoreAction.addEventListener('click', () => {
  void runAction('restore_last_good', '正在恢复插件 profile 并重新加载 Harness…')
})
safeModeAction.addEventListener('click', () => {
  void runAction('start_safe_mode', '正在准备安全模式并重新加载 Harness…')
})
retryAction.addEventListener('click', () => {
  void runAction('retry_harness', '正在重新启动 Harness…')
})

async function copyText(text, button) {
  try {
    await navigator.clipboard.writeText(text)
  } catch {
    const input = document.createElement('textarea')
    input.value = text
    input.setAttribute('readonly', '')
    input.style.position = 'fixed'
    input.style.opacity = '0'
    document.body.append(input)
    input.select()
    document.execCommand('copy')
    input.remove()
  }
  const original = button.textContent
  button.textContent = '已复制'
  window.setTimeout(() => { button.textContent = original }, 1_500)
}

copyError.addEventListener('click', event => {
  event.preventDefault()
  void copyText(errorNode.textContent, copyError)
})

async function initialize() {
  await loadStatus()
  const action = new URLSearchParams(window.location.search).get('dsh-desktop-action')
  if (action === 'retry') {
    window.history.replaceState({}, '', window.location.pathname)
    await runAction('retry_harness', '正在退出安全模式并尝试普通启动…')
  }
}

void initialize()
