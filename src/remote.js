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
  const RESUME_STALL_TIMEOUT_MS = 12000
  const LAN_TRANSPORT = 'lan'
  const TAILSCALE_TRANSPORT = 'tailscale'
  const RESUME_OPERATION_PARAMETER = 'dsh-desktop-remote-operation'
  const TAILSCALE_PROGRESS_STEPS = Object.freeze([
    'checking',
    'restarting',
    'serving',
    'pairing',
  ])
  const ALLOWED_ACTIONS = new Set([
    'remote-status',
    'remote-open-https',
    'remote-enable',
    'remote-disable',
    'remote-lan-enable',
    'remote-lan-disable',
    'remote-lan-reset',
    'remote-presented',
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

  function normalizeOperation(value) {
    const operation = value && typeof value === 'object' ? value : {}
    return Object.freeze({
      id: String(operation.id || ''),
      transport: String(operation.transport || ''),
      action: String(operation.action || ''),
      stage: String(operation.stage || ''),
      active: Boolean(operation.active),
      error: String(operation.error || ''),
      presentationHandoffReady: Boolean(operation.presentationHandoffReady),
    })
  }

  function normalizeStatus(value) {
    const provided = Boolean(value && typeof value === 'object')
    const status = provided ? value : {}
    const hasStatusReady = Object.prototype.hasOwnProperty.call(status, 'statusReady')
    const hasTailscaleStatusReady = Object.prototype.hasOwnProperty.call(
      status,
      'tailscaleStatusReady',
    )
    return Object.freeze({
      statusReady: hasStatusReady ? Boolean(status.statusReady) : provided,
      tailscaleStatusReady: hasTailscaleStatusReady
        ? Boolean(status.tailscaleStatusReady)
        : provided,
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
      operation: normalizeOperation(status.operation),
    })
  }

  function normalizedOperationStage(value) {
    const stage = String(value || '').trim().toLowerCase().replaceAll('_', '-')
    if (!stage) return 'checking'
    if (/(error|fail|rollback-failed)/.test(stage)) return 'error'
    if (/(ready|complete|completed|success|done|\bon\b)/.test(stage)) return 'ready'
    if (/(pair|qr|credential|code)/.test(stage)) return 'pairing'
    if (/(serve|tunnel|proxy|entry|endpoint|secure)/.test(stage)) return 'serving'
    if (/(restart|harness|stopping|launching|relaunch)/.test(stage)) return 'restarting'
    return 'checking'
  }

  function operationProgress(value) {
    const operation = normalizeOperation(value)
    const normalizedStage = operation.error ? 'error' : normalizedOperationStage(operation.stage)
    const terminal = normalizedStage === 'error'
      ? 'error'
      : (!operation.active && normalizedStage === 'ready' ? 'ready' : '')
    let stepIndex = TAILSCALE_PROGRESS_STEPS.indexOf(normalizedStage)
    if (normalizedStage === 'ready') stepIndex = TAILSCALE_PROGRESS_STEPS.length
    if (normalizedStage === 'error') stepIndex = -1
    return Object.freeze({
      operation,
      normalizedStage,
      stepIndex,
      terminal,
    })
  }

  function shouldRestoreOperation(resumeId, value) {
    const operation = normalizeOperation(value)
    return Boolean(resumeId) && operation.id === String(resumeId)
  }

  function shouldDeferTerminalPresentation(resumeId, value) {
    const operation = normalizeOperation(value)
    return operation.presentationHandoffReady && !shouldRestoreOperation(resumeId, operation)
  }

  function shouldAutoOpenLanPairing(requested, previous, next) {
    const before = normalizeStatus(previous)
    const after = normalizeStatus(next)
    return Boolean(requested)
      && after.lanEnabled
      && Boolean(after.lanQrSvg)
      && (!before.lanEnabled || before.lanPairingURL !== after.lanPairingURL)
  }

  function shouldPollStatus(value, surfaceVisible, pageVisible = true, requestInFlight = false) {
    const next = normalizeStatus(value)
    return Boolean(surfaceVisible)
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
          checkingConnections: '正在检查可用的连接方式…',
          checkingLocal: '正在确认 Harness 与本地网络状态。',
          checkingTailscale: '正在检查 Tailscale…',
          localReadyCheckingTailscale: '本地连接状态已确认，仍在检查 Tailscale。',
          lanSummaryActive: '同一 Wi-Fi 连接已开启，可随时重新显示配对码。',
          tailscaleSummaryActive: '跨网络连接已开启；同一 Wi-Fi 配对仍可独立使用。',
          bothSummaryActive: '同一 Wi-Fi 与跨网络连接均已开启。',
          lanTitle: '同一 Wi-Fi',
          lanBadge: '推荐',
          lanDescription: 'iPhone 与电脑连接同一个可信 Wi-Fi，无需安装或配置 Tailscale。',
          lanChecking: '正在检查本地连接能力…',
          lanUnavailable: 'Harness 启动完成后即可开始本地配对。',
          lanActive: '本地连接已开启：{url}',
          lanStart: '开始本地配对',
          lanStarting: '正在准备本地连接…',
          lanStop: '关闭本地连接',
          lanStopping: '正在关闭本地连接…',
          lanPair: '显示配对码',
          lanReset: '重置配对',
          lanResetTitle: '重置同一 Wi-Fi 配对？',
          lanResetBody: '当前二维码和所有已保存它的 iPhone 将立即失效。',
          lanResetRevoke: '已经配对的 iPhone 需要重新扫描二维码。',
          lanResetKeepAddress: '电脑地址保持不变，只更换访问凭据。',
          lanResetConfirm: '重置配对',
          tailscaleTitle: '跨网络连接',
          tailscaleBadge: '可选',
          tailscaleDescription: '离开本地 Wi-Fi 时，通过你自己的 Tailscale 网络连接。',
          tailscaleChecking: '正在检查 Tailscale 状态…',
          unavailable: '需要先在电脑和 iPhone 安装 Tailscale，并登录同一个 Tailnet。',
          disconnected: 'Tailscale 尚未连接；这不会影响同一 Wi-Fi 配对。',
          magicDNS: '当前 Tailnet 需要开启 MagicDNS；这不会影响同一 Wi-Fi 配对。',
          https: '还需在 Tailscale 管理页启用 HTTPS。',
          setupHTTPS: '设置 HTTPS',
          guide: '设置指南',
          guideTitle: 'Tailscale 跨网络设置',
          guideBody: '大约 3 分钟。Desktop 会自动配置安全入口，不需要复制终端命令。',
          guideStatusChecking: '正在检查 Tailscale',
          guideStatusInstall: '下一步：在 Mac 安装 Tailscale',
          guideStatusConnect: '下一步：登录并连接 Tailscale',
          guideStatusMagicDNS: '下一步：开启 MagicDNS',
          guideStatusHTTPS: '下一步：授权 Tailnet HTTPS',
          guideStatusReady: 'Tailscale 已准备好',
          guideStepMacTitle: '在 Mac 安装并登录',
          guideStepMacDetail: '安装 Tailscale，并用你的账号登录。Standalone 版本最适合普通 Mac 用户。',
          guideStepIPhoneTitle: '在 iPhone 登录同一账号',
          guideStepIPhoneDetail: '安装 Tailscale，允许 VPN 配置，并确认 Mac 与 iPhone 出现在同一个 Tailnet。',
          guideStepDNSHTitle: '完成 DNS 与 HTTPS 授权',
          guideStepDNSDetail: '按 Desktop 提示开启 MagicDNS 和 HTTPS。启用证书会把设备 DNS 名称写入公开证书日志。',
          guideStepEnableTitle: '回到 Desktop 开启跨网络',
          guideStepEnableDetail: 'Desktop 会自动配置 Tailscale Serve 和 Harness，不需要手动运行命令。',
          guideStepTestTitle: '用蜂窝网络验收',
          guideStepTestDetail: '在 Remote 扫描二维码，然后关闭 iPhone Wi-Fi，只保留蜂窝网络和 Tailscale 再发送一条消息。',
          guideMacLink: '下载 Mac 版',
          guideIPhoneLink: '下载 iPhone 版',
          guideDNSLink: '打开 Tailnet DNS 设置',
          guideHelpLink: '查看 Tailscale 官方说明',
          guideSafety: '只使用 Tailscale Serve。不要开启 Funnel；Funnel 会把入口暴露到公网。',
          active: '跨网络连接已开启：{url}',
          enable: '开启跨网络',
          enabling: '正在开启跨网络连接…',
          disable: '关闭跨网络',
          disabling: '正在关闭跨网络连接…',
          pair: '显示配对码',
          restart: '开启跨网络连接会重启 Harness，并中断正在运行的任务。',
          confirmTitle: '开启跨网络连接？',
          confirmBody: '需要重启 Harness 才能安全地开放跨网络入口。',
          confirmInterrupt: '正在运行的任务会中断。',
          confirmReturn: '完成后会自动回到这里，并显示配对码。',
          cancel: '取消',
          restartAndEnable: '重启并开启',
          operationTitle: '正在开启跨网络连接',
          operationChecking: '检查 Tailscale',
          operationRestarting: '重启 Harness',
          operationServing: '启动安全入口',
          operationPairing: '生成配对码',
          operationCheckingDetail: '正在确认 Tailscale、MagicDNS 与 HTTPS 配置。',
          operationRestartingDetail: 'Harness 正在重新启动，完成后会继续当前设置。',
          operationServingDetail: '正在建立仅供你的 Tailnet 使用的安全入口。',
          operationPairingDetail: '连接入口已就绪，正在生成一次性配对信息。',
          operationErrorTitle: '跨网络连接未开启',
          operationErrorFallback: '设置没有完成。你仍可以返回并使用同一 Wi-Fi 配对。',
          disableOperationTitle: '正在关闭跨网络连接',
          disableStopping: '关闭安全入口',
          disableStoppingDetail: '正在停止跨网络入口。',
          disableRestarting: '恢复 Harness',
          disableRestartingDetail: 'Harness 正在恢复普通连接模式，完成后会自动回到这里。',
          disableErrorTitle: '跨网络连接未能关闭',
          resumeMissing: '刚才的设置状态已经结束，请重新检查连接方式。',
          resumeTakingLong: '正在重新检查跨网络状态',
          resumeTakingLongDetail: '恢复页面没有收到最新状态，已返回主界面。Tailscale 设置仍会继续接受检查。',
          hide: '隐藏',
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
          checkingConnections: 'Checking available connection options…',
          checkingLocal: 'Checking Harness and the local network.',
          checkingTailscale: 'Checking Tailscale…',
          localReadyCheckingTailscale: 'Local connection status is ready while Tailscale is still being checked.',
          lanSummaryActive: 'Same Wi-Fi is on. You can show the pairing code again at any time.',
          tailscaleSummaryActive: 'Anywhere access is on. Same Wi-Fi pairing remains independently available.',
          bothSummaryActive: 'Same Wi-Fi and anywhere access are both on.',
          lanTitle: 'Same Wi-Fi',
          lanBadge: 'Recommended',
          lanDescription: 'Connect iPhone and this computer to the same trusted Wi-Fi. Tailscale is not required.',
          lanChecking: 'Checking local connection availability…',
          lanUnavailable: 'Local pairing is available after Harness finishes starting.',
          lanActive: 'Local connection is on: {url}',
          lanStart: 'Start local pairing',
          lanStarting: 'Preparing local connection…',
          lanStop: 'Turn off local connection',
          lanStopping: 'Turning off local connection…',
          lanPair: 'Show pairing code',
          lanReset: 'Reset pairing',
          lanResetTitle: 'Reset same-Wi-Fi pairing?',
          lanResetBody: 'The current QR code and every iPhone that saved it will stop working immediately.',
          lanResetRevoke: 'Previously paired iPhones must scan the new QR code.',
          lanResetKeepAddress: 'The computer address stays the same; only the access credential changes.',
          lanResetConfirm: 'Reset pairing',
          tailscaleTitle: 'Connect from anywhere',
          tailscaleBadge: 'Optional',
          tailscaleDescription: 'Use your own Tailscale network when iPhone is away from local Wi-Fi.',
          tailscaleChecking: 'Checking Tailscale status…',
          unavailable: 'Install Tailscale on this computer and iPhone, then sign in to the same tailnet.',
          disconnected: 'Tailscale is not connected. Same Wi-Fi pairing is still available.',
          magicDNS: 'MagicDNS must be enabled for this tailnet. Same Wi-Fi pairing is unaffected.',
          https: 'Enable HTTPS in the Tailscale admin console to continue.',
          setupHTTPS: 'Set up HTTPS',
          guide: 'Setup guide',
          guideTitle: 'Set up Tailscale access',
          guideBody: 'About 3 minutes. Desktop configures the secure entry automatically—no terminal commands to copy.',
          guideStatusChecking: 'Checking Tailscale',
          guideStatusInstall: 'Next: install Tailscale on this Mac',
          guideStatusConnect: 'Next: sign in and connect Tailscale',
          guideStatusMagicDNS: 'Next: enable MagicDNS',
          guideStatusHTTPS: 'Next: authorize tailnet HTTPS',
          guideStatusReady: 'Tailscale is ready',
          guideStepMacTitle: 'Install and sign in on Mac',
          guideStepMacDetail: 'Install Tailscale and sign in with your account. The Standalone variant is recommended for most Mac users.',
          guideStepIPhoneTitle: 'Use the same account on iPhone',
          guideStepIPhoneDetail: 'Install Tailscale, allow the VPN configuration, and confirm the Mac and iPhone are in the same tailnet.',
          guideStepDNSHTitle: 'Authorize DNS and HTTPS',
          guideStepDNSDetail: 'Follow Desktop prompts for MagicDNS and HTTPS. Certificate names are recorded in public certificate logs.',
          guideStepEnableTitle: 'Enable anywhere access in Desktop',
          guideStepEnableDetail: 'Desktop configures Tailscale Serve and Harness automatically. No manual command is required.',
          guideStepTestTitle: 'Test over cellular',
          guideStepTestDetail: 'Scan the QR code in Remote, turn off iPhone Wi-Fi, keep cellular and Tailscale on, then send a message.',
          guideMacLink: 'Download for Mac',
          guideIPhoneLink: 'Download for iPhone',
          guideDNSLink: 'Open tailnet DNS settings',
          guideHelpLink: 'Read the official Tailscale guide',
          guideSafety: 'Use Tailscale Serve only. Do not enable Funnel; Funnel exposes the entry to the public internet.',
          active: 'Anywhere connection is on: {url}',
          enable: 'Connect from anywhere',
          enabling: 'Preparing anywhere connection…',
          disable: 'Turn off anywhere access',
          disabling: 'Turning off anywhere access…',
          pair: 'Show pairing code',
          restart: 'Turning on anywhere access restarts Harness and interrupts running tasks.',
          confirmTitle: 'Connect from anywhere?',
          confirmBody: 'Harness must restart to open the private network entry safely.',
          confirmInterrupt: 'Any running tasks will be interrupted.',
          confirmReturn: 'When it finishes, this panel returns automatically with the pairing code.',
          cancel: 'Cancel',
          restartAndEnable: 'Restart and connect',
          operationTitle: 'Preparing anywhere access',
          operationChecking: 'Check Tailscale',
          operationRestarting: 'Restart Harness',
          operationServing: 'Start secure entry',
          operationPairing: 'Create pairing code',
          operationCheckingDetail: 'Checking Tailscale, MagicDNS, and HTTPS configuration.',
          operationRestartingDetail: 'Harness is restarting. Setup will continue here automatically.',
          operationServingDetail: 'Creating a secure entry available only inside your tailnet.',
          operationPairingDetail: 'The entry is ready. Creating one-time pairing information.',
          operationErrorTitle: 'Anywhere access was not enabled',
          operationErrorFallback: 'Setup did not finish. You can still go back and pair on the same Wi-Fi.',
          disableOperationTitle: 'Turning off anywhere access',
          disableStopping: 'Stop secure entry',
          disableStoppingDetail: 'Stopping the private network entry.',
          disableRestarting: 'Restore Harness',
          disableRestartingDetail: 'Harness is returning to its normal connection mode. This panel will resume automatically.',
          disableErrorTitle: 'Anywhere access could not be turned off',
          resumeMissing: 'The previous setup has ended. Check the connection options again.',
          resumeTakingLong: 'Rechecking anywhere access',
          resumeTakingLongDetail: 'The recovery page did not receive fresh status, so the main interface was restored while Tailscale is checked again.',
          hide: 'Hide',
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

  function tailscaleGuideState(value, language = 'en') {
    const next = normalizeStatus(value)
    const copy = copyFor(languageFromTag(language))
    if (!next.tailscaleStatusReady) {
      return Object.freeze({ key: 'checking', title: copy.guideStatusChecking, detail: copy.tailscaleChecking })
    }
    if (!next.installed) {
      return Object.freeze({ key: 'install', title: copy.guideStatusInstall, detail: copy.unavailable })
    }
    if (next.backendState !== 'Running') {
      return Object.freeze({ key: 'connect', title: copy.guideStatusConnect, detail: copy.disconnected })
    }
    if (!next.magicDNS) {
      return Object.freeze({ key: 'magicdns', title: copy.guideStatusMagicDNS, detail: copy.magicDNS })
    }
    if (!next.httpsReady) {
      return Object.freeze({ key: 'https', title: copy.guideStatusHTTPS, detail: copy.https })
    }
    return Object.freeze({
      key: 'ready',
      title: copy.guideStatusReady,
      detail: next.enabled ? copy.active.replace('{url}', next.url) : copy.tailscaleDescription,
    })
  }

  function authoritativeOperationOutcome(value, statusValue) {
    const operation = normalizeOperation(value)
    const next = normalizeStatus(statusValue)
    if (!isTailscaleOperation(operation)) return ''
    if (isTailscaleEnableOperation(operation) && next.enabled && Boolean(next.qrSvg)) {
      return 'enable-ready'
    }
    if (isDisableOperation(operation) && next.statusReady && !next.busy && !next.enabled) {
      return 'disable-ready'
    }
    return ''
  }

  function transportViewState(
    value,
    transport,
    language = 'en',
    pendingAction = '',
    otherPendingAction = '',
  ) {
    const next = normalizeStatus(value)
    const copy = copyFor(languageFromTag(language))
    const lan = transport === LAN_TRANSPORT
    const enabled = lan ? next.lanEnabled : next.enabled
    const nativeBusy = lan ? next.lanBusy : next.busy
    const otherNativeBusy = lan ? next.busy : next.lanBusy
    const operationTransport = next.operation.transport === LAN_TRANSPORT
      ? LAN_TRANSPORT
      : TAILSCALE_TRANSPORT
    const operationBusy = next.operation.active && operationTransport === transport
    const otherOperationBusy = next.operation.active && operationTransport !== transport
    const checking = lan ? !next.statusReady : !next.tailscaleStatusReady
    const busy = checking || nativeBusy || operationBusy || Boolean(pendingAction)
    const blocked = !busy && (otherNativeBusy || otherOperationBusy || Boolean(otherPendingAction))
    const endpoint = lan ? next.lanURL : next.url
    const error = lan ? next.lanError : next.error
    const stopping = pendingAction.endsWith('-disable')
      || (!pendingAction && nativeBusy && enabled)
      || (!lan && next.phase === 'stopping')

    let description
    let hasError = false
    if (checking) {
      description = lan ? copy.lanChecking : copy.tailscaleChecking
    } else if (busy) {
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
    let actionDisabled = busy || blocked
    if (lan) {
      action = enabled ? 'remote-lan-disable' : 'remote-lan-enable'
      actionLabel = checking
        ? copy.lanChecking
        : busy
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
      actionLabel = checking ? copy.tailscaleChecking : busy ? copy.enabling : copy.enable
      actionDisabled ||= !(next.installed
        && next.backendState === 'Running'
        && next.magicDNS
        && next.httpsReady)
    }
    if (checking) actionLabel = lan ? copy.lanChecking : copy.tailscaleChecking

    return Object.freeze({
      action,
      actionDisabled,
      actionLabel,
      blocked,
      busy,
      checking,
      description,
      enabled,
      hasError,
      pairDisabled: busy || blocked || !(lan ? next.lanQrSvg : next.qrSvg),
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
    if (pendingAction.endsWith('-reset')) return ''
    return pendingAction
  }

  const testGlobal = typeof globalThis === 'undefined' ? null : globalThis
  if (testGlobal?.[TEST_FLAG] === true) {
    testGlobal[TEST_API] = Object.freeze({
      actionUrl,
      authoritativeOperationOutcome,
      copyFor,
      languageFromTag,
      normalizeOperation,
      normalizeStatus,
      normalizedOperationStage,
      operationProgress,
      pendingActionAfterStatus,
      shouldPollStatus,
      shouldDeferTerminalPresentation,
      shouldRestoreOperation,
      shouldAutoOpenLanPairing,
      statusAfterError,
      tailscaleGuideState,
      transportViewState,
    })
    return
  }

  if (typeof window === 'undefined' || typeof document === 'undefined') return
  if (location.protocol !== 'http:' || location.hostname !== '127.0.0.1') return

  function resumeOperationIdFromLocation(value = location.href) {
    try {
      return new URL(value).searchParams.get(RESUME_OPERATION_PARAMETER) || ''
    } catch {
      return ''
    }
  }

  const resumeCurtainShadows = new WeakMap()

  function createResumeCurtain(operationId) {
    if (!operationId || document.getElementById(`${LAYER_ID}-resume`)) return null
    const host = document.createElement('div')
    host.id = `${LAYER_ID}-resume`
    const shadow = host.attachShadow({ mode: 'closed' })
    const copy = copyFor(currentLanguage())
    shadow.innerHTML = `
      <style>
        :host{all:initial;position:fixed;z-index:2147483003;inset:0;display:grid;place-items:center;background:var(--dsw-alias-bg-layer-1,#111318);color:var(--dsw-alias-label-primary,#f4f5f7);font:13px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
        *{box-sizing:border-box}.resume{display:flex;width:min(420px,calc(100vw - 48px));align-items:flex-start;gap:13px;border:1px solid var(--dsw-alias-border-l2,rgba(255,255,255,.12));border-radius:16px;padding:18px;background:color-mix(in srgb,var(--dsw-alias-bg-layer-3,#24262c) 94%,transparent);box-shadow:0 22px 70px rgba(0,0,0,.28);backdrop-filter:blur(20px) saturate(130%)}
        .spinner{flex:0 0 auto;width:18px;height:18px;margin-top:1px;border:2px solid color-mix(in srgb,var(--dsw-alias-state-business-primary,#4f8cff) 24%,transparent);border-top-color:var(--dsw-alias-state-business-primary,#4f8cff);border-radius:50%;animation:spin .8s linear infinite}.title{font-size:14px;font-weight:600;line-height:20px}.detail{margin-top:3px;color:var(--dsw-alias-label-tertiary,#a6a9b1);font-size:12px;line-height:18px}@keyframes spin{to{transform:rotate(360deg)}}
        @media(prefers-reduced-motion:reduce){.spinner{animation:none;border-color:var(--dsw-alias-state-business-primary,#4f8cff)}}
        @media(prefers-reduced-transparency:reduce){.resume{background:var(--dsw-alias-bg-layer-3,#24262c);backdrop-filter:none}}
        @media(prefers-contrast:more){.resume{border:2px solid currentColor}}
      </style>
      <div class="resume" role="status" aria-live="polite" aria-atomic="true">
        <span class="spinner" aria-hidden="true"></span>
        <div><div class="title"></div><div class="detail"></div></div>
      </div>
    `
    shadow.querySelector('.title').textContent = copy.operationTitle
    shadow.querySelector('.detail').textContent = copy.operationRestartingDetail
    resumeCurtainShadows.set(host, shadow)
    const parent = document.documentElement || document.body
    if (!parent) return null
    parent.append(host)
    return host
  }

  function updateResumeCurtainCopy() {
    const shadow = resumeCurtain && resumeCurtainShadows.get(resumeCurtain)
    if (!shadow) return
    const copy = copyFor(currentLanguage())
    shadow.querySelector('.title').textContent = copy.operationTitle
    shadow.querySelector('.detail').textContent = copy.operationRestartingDetail
  }

  const resumeOperationId = resumeOperationIdFromLocation()
  let resumeCurtain = createResumeCurtain(resumeOperationId)
  let resumeRecoveryTimer = 0

  function armResumeRecoveryTimer() {
    if (resumeRecoveryTimer) window.clearTimeout(resumeRecoveryTimer)
    resumeRecoveryTimer = resumeCurtain
      ? window.setTimeout(recoverStalledResume, RESUME_STALL_TIMEOUT_MS)
      : 0
  }

  armResumeRecoveryTimer()

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
  let tailscaleGuideButton = null
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
  let lanAutoPairRequested = false
  let visibleOperationId = ''
  let acknowledgedOperationId = ''
  let operationResumeSettled = false
  let dismissedOperationId = ''
  let tailscaleOperationRequested = ''
  let confirmationAction = ''

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
    else {
      pendingTailscaleAction = action
      if (action === 'remote-enable' || action === 'remote-disable') {
        tailscaleOperationRequested = action
      }
    }
    const timeout = window.setTimeout(() => {
      clearPendingAction(transport)
      if (transport === LAN_TRANSPORT) lanAutoPairRequested = false
      updateSetting()
      refreshStatus(true)
    }, ACTION_ACK_TIMEOUT_MS)
    if (transport === LAN_TRANSPORT) pendingLanTimer = timeout
    else pendingTailscaleTimer = timeout
  }

  function requestTransportAction(action, transport) {
    lastActionTransport = transport
    if (transport === LAN_TRANSPORT) {
      if (action === 'remote-lan-enable' || action === 'remote-lan-reset') {
        lanAutoPairRequested = true
      }
      if (action === 'remote-lan-disable') lanAutoPairRequested = false
    }
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

  function configureButton(button, label, className, disabled, hidden = false, busy = false) {
    if (busy) {
      const spinner = document.createElement('span')
      spinner.className = 'dsh-remote-spinner'
      spinner.setAttribute('aria-hidden', 'true')
      const text = document.createElement('span')
      text.textContent = label
      button.replaceChildren(spinner, text)
    } else {
      button.textContent = label
    }
    button.setAttribute('aria-label', label)
    button.className = className
    button.disabled = Boolean(disabled && !busy)
    button.setAttribute('aria-disabled', String(Boolean(disabled)))
    button.toggleAttribute('data-busy', busy)
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
    route.toggleAttribute('data-blocked', view.blocked)
    route.toggleAttribute('data-error', view.hasError)
    route.setAttribute('aria-busy', String(view.busy))
    configureButton(
      actionButton,
      view.actionLabel,
      view.enabled || !lan ? '' : 'dsh-remote-primary',
      view.actionDisabled,
      false,
      view.busy,
    )
    configureButton(pairButton, view.pairLabel, 'dsh-remote-primary', view.pairDisabled, !view.enabled)
  }

  function isDisableOperation(value) {
    return normalizeOperation(value).action.includes('disable')
  }

  function operationCopy(copy, progress) {
    if (isDisableOperation(progress.operation)) {
      if (progress.normalizedStage === 'restarting') {
        return { label: copy.disableRestarting, detail: copy.disableRestartingDetail }
      }
      return { label: copy.disableStopping, detail: copy.disableStoppingDetail }
    }
    const { normalizedStage } = progress
    if (normalizedStage === 'restarting') {
      return { label: copy.operationRestarting, detail: copy.operationRestartingDetail }
    }
    if (normalizedStage === 'serving') {
      return { label: copy.operationServing, detail: copy.operationServingDetail }
    }
    if (normalizedStage === 'pairing') {
      return { label: copy.operationPairing, detail: copy.operationPairingDetail }
    }
    return { label: copy.operationChecking, detail: copy.operationCheckingDetail }
  }

  function setStatusSymbol(kind) {
    const symbol = layerShadow?.querySelector('.status-symbol')
    if (!symbol) return
    if (kind === 'busy') {
      const spinner = document.createElement('span')
      spinner.className = 'dsh-remote-spinner'
      spinner.setAttribute('aria-hidden', 'true')
      symbol.replaceChildren(spinner)
    } else {
      symbol.textContent = kind === 'error' ? '!' : '✓'
    }
  }

  function renderProgressSteps(progress, copy) {
    const list = layerShadow?.querySelector('.progress-steps')
    if (!list) return
    const disabling = isDisableOperation(progress.operation)
    const labels = disabling
      ? [copy.disableStopping, copy.disableRestarting]
      : [
          copy.operationChecking,
          copy.operationRestarting,
          copy.operationServing,
          copy.operationPairing,
        ]
    const currentIndex = disabling
      ? progress.normalizedStage === 'ready'
        ? labels.length
        : progress.normalizedStage === 'restarting' ? 1 : 0
      : progress.stepIndex
    list.dataset.count = String(labels.length)
    list.replaceChildren(...labels.map((label, index) => {
      const item = document.createElement('li')
      item.className = 'progress-step'
      item.textContent = label
      const state = index < currentIndex
        ? 'done'
        : index === currentIndex && !progress.terminal
          ? 'current'
          : 'pending'
      item.dataset.state = state
      if (state === 'current') item.setAttribute('aria-current', 'step')
      return item
    }))
    list.hidden = false
  }

  function renderManagerStatus({ detail, kind = 'busy', progress = null, title }) {
    const panel = layerShadow?.querySelector('.manager-status')
    if (!panel) return
    panel.hidden = false
    panel.dataset.kind = kind
    panel.setAttribute('role', kind === 'error' ? 'alert' : 'status')
    panel.setAttribute('aria-live', kind === 'error' ? 'assertive' : 'polite')
    layerShadow.querySelector('.status-title').textContent = title
    layerShadow.querySelector('.status-detail').textContent = detail
    setStatusSymbol(kind)
    const list = layerShadow.querySelector('.progress-steps')
    if (progress) renderProgressSteps(progress, copyFor(currentLanguage()))
    else {
      list.hidden = true
      list.replaceChildren()
    }
  }

  function renderProbeStatus() {
    if (!layerShadow || layerShadow.querySelector('.chooser').hidden) return
    const panel = layerShadow.querySelector('.manager-status')
    if (status.statusReady && status.tailscaleStatusReady) {
      panel.hidden = true
      return
    }
    const copy = copyFor(currentLanguage())
    renderManagerStatus({
      title: copy.checkingConnections,
      detail: !status.statusReady
        ? copy.checkingLocal
        : copy.localReadyCheckingTailscale,
    })
  }

  function showDialogPanel(name) {
    if (!layerShadow) return
    layerShadow.querySelector('.chooser').hidden = name !== 'chooser'
    layerShadow.querySelector('.confirm').hidden = name !== 'confirm'
    layerShadow.querySelector('.pairing').hidden = name !== 'pairing'
    layerShadow.querySelector('.tailscale-guide').hidden = name !== 'guide'
    layerShadow.querySelector('.reset').hidden = name !== 'pairing'
      || pairingTransport !== LAN_TRANSPORT
    if (name !== 'operation' && name !== 'chooser') {
      layerShadow.querySelector('.manager-status').hidden = true
    }
  }

  function renderOperationManager(value, rememberFocus = false) {
    const operation = normalizeOperation(value)
    const progress = operationProgress(operation)
    const copy = copyFor(currentLanguage())
    ensureLayer()
    if (rememberFocus && layer.hidden) pairingReturnFocus = document.activeElement
    const wasHidden = layer.hidden
    visibleOperationId = operation.id
    layerShadow.querySelector('h2').textContent = copy.connect
    layerShadow.querySelector('.body').textContent = copy.managerBody
    showDialogPanel('operation')
    layerShadow.querySelector('.back').hidden = !progress.terminal
    layerShadow.querySelector('.back').textContent = copy.back
    layerShadow.querySelector('.copy').hidden = true
    layerShadow.querySelector('.close').hidden = false
    layerShadow.querySelector('.close').textContent = operation.active ? copy.hide : copy.managerClose
    const operationText = operationCopy(copy, progress)
    renderManagerStatus({
      title: progress.terminal === 'error'
        ? isDisableOperation(operation) ? copy.disableErrorTitle : copy.operationErrorTitle
        : isDisableOperation(operation) ? copy.disableOperationTitle : copy.operationTitle,
      detail: progress.terminal === 'error'
        ? operation.error || copy.operationErrorFallback
        : operationText.detail,
      kind: progress.terminal === 'error' ? 'error' : 'busy',
      progress: progress.terminal === 'error' ? null : progress,
    })
    layer.hidden = false
    resumeCurtain?.remove()
    resumeCurtain = null
    if (wasHidden) layerShadow.querySelector('h2').focus()
  }

  function updateSetting() {
    const copy = copyFor(currentLanguage())
    const lanView = transportViewState(
      status,
      LAN_TRANSPORT,
      currentLanguage(),
      pendingLanAction,
      pendingTailscaleAction,
    )
    const tailscaleView = transportViewState(
      status,
      TAILSCALE_TRANSPORT,
      currentLanguage(),
      pendingTailscaleAction,
      pendingLanAction,
    )
    if (settingRow && settingTitle && settingDescription && settingConnectButton) {
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
    }
    if (!lanRoute || !tailscaleRoute) return
    lanRoute.querySelector('.dsh-remote-route-title').textContent = copy.lanTitle
    lanRoute.querySelector('.dsh-remote-badge').textContent = copy.lanBadge
    tailscaleRoute.querySelector('.dsh-remote-route-title').textContent = copy.tailscaleTitle
    tailscaleRoute.querySelector('.dsh-remote-badge').textContent = copy.tailscaleBadge
    if (tailscaleGuideButton) tailscaleGuideButton.textContent = copy.guide
    renderTransport(LAN_TRANSPORT, lanView)
    renderTransport(TAILSCALE_TRANSPORT, tailscaleView)
    renderProbeStatus()
    if (layerShadow && !layerShadow.querySelector('.tailscale-guide').hidden) {
      renderTailscaleGuide()
    }
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
    let guideButton = null
    if (transport === TAILSCALE_TRANSPORT) {
      guideButton = createButton('', 'dsh-remote-guide-link', openTailscaleGuide)
      heading.append(guideButton)
    }
    const description = document.createElement('p')
    description.className = 'dsh-remote-route-description'
    description.id = `dsh-remote-${transport}-description`
    const controls = document.createElement('div')
    controls.className = 'dsh-remote-controls'
    const actionButton = createButton('', 'dsh-remote-primary', () => {
      const pendingAction = transport === LAN_TRANSPORT ? pendingLanAction : pendingTailscaleAction
      const otherPendingAction = transport === LAN_TRANSPORT
        ? pendingTailscaleAction
        : pendingLanAction
      const view = transportViewState(
        status,
        transport,
        currentLanguage(),
        pendingAction,
        otherPendingAction,
      )
      if (view.actionDisabled) return
      if (transport === TAILSCALE_TRANSPORT && view.action === 'remote-enable') {
        openTailscaleConfirmation()
        return
      }
      requestTransportAction(view.action, transport)
    })
    actionButton.setAttribute('aria-describedby', description.id)
    const pairButton = createButton('', 'dsh-remote-primary', () => openPairing(transport), true)
    pairButton.setAttribute('aria-describedby', description.id)
    controls.append(actionButton, pairButton)
    route.append(heading, description, controls)
    return { actionButton, description, guideButton, pairButton, route }
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
        :host{all:initial}:host([hidden]){display:none}*{box-sizing:border-box}[hidden]{display:none!important}
        .backdrop{position:fixed;z-index:2147483002;inset:0;display:grid;place-items:center;overflow:auto;padding:24px;background:rgba(9,16,29,.5);font:13px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
        .dialog{width:min(580px,100%);max-height:calc(100vh - 48px);overflow:auto;border:1px solid var(--dsw-alias-border-l2,#dbe1ea);border-radius:18px;padding:22px;background:color-mix(in srgb,var(--dsw-alias-bg-layer-3,#fff) 96%,transparent);color:var(--dsw-alias-label-primary,#111827);box-shadow:0 24px 80px rgba(0,0,0,.28);backdrop-filter:blur(24px) saturate(135%);animation:materialize 180ms cubic-bezier(.2,.8,.2,1)}
        h2,h3,p{margin:0}h2{font-size:19px;font-weight:650;line-height:26px;letter-spacing:-.012em}h2:focus{outline:none}.body{margin-top:6px;color:var(--dsw-alias-label-tertiary,#64748b)}
        .dialog-view{animation:view-in 150ms ease-out}.chooser-routes{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);gap:10px;margin-top:18px}
        .dsh-remote-route{min-width:0;border:1px solid var(--dsw-alias-border-l2,#dbe1ea);border-radius:13px;padding:13px;background:var(--dsw-alias-bg-layer-1,#f1f5f9);transition:border-color 160ms ease,background-color 160ms ease,transform 160ms ease}
        .dsh-remote-route[data-kind="lan"]{border-color:color-mix(in srgb,var(--dsw-alias-state-business-primary,#2563eb) 32%,var(--dsw-alias-border-l2,#dbe1ea));background:color-mix(in srgb,var(--dsw-alias-state-business-primary,#2563eb) 5%,var(--dsw-alias-bg-layer-1,#f1f5f9))}.dsh-remote-route[data-busy]{border-color:var(--dsw-alias-state-business-primary,#2563eb)}.dsh-remote-route[data-error]{border-color:color-mix(in srgb,var(--dsw-alias-state-error-primary,#dc2626) 52%,var(--dsw-alias-border-l2,#dbe1ea))}
        .dsh-remote-route-heading{display:flex;align-items:center;gap:7px;min-height:28px}.dsh-remote-route-title{margin:0;color:var(--dsw-alias-label-primary,#111827);font-size:13px;font-weight:600;line-height:20px}.dsh-remote-badge{border-radius:999px;padding:1px 7px;background:var(--dsw-alias-bg-layer-3,#fff);color:var(--dsw-alias-label-tertiary,#64748b);font-size:10px;font-weight:600;line-height:17px}.dsh-remote-route[data-kind="lan"] .dsh-remote-badge{background:color-mix(in srgb,var(--dsw-alias-state-business-primary,#2563eb) 12%,transparent);color:var(--dsw-alias-state-business-primary,#2563eb)}.dsh-remote-guide-link{min-height:28px;margin-left:auto;border:0;padding:4px 6px;background:transparent;color:var(--dsw-alias-state-business-primary,#2563eb);font-size:11px}.dsh-remote-guide-link:hover:not(:disabled){background:color-mix(in srgb,var(--dsw-alias-state-business-primary,#2563eb) 8%,transparent)}
        .dsh-remote-route-description{min-height:54px;margin:5px 0 0;color:var(--dsw-alias-label-tertiary,#64748b);font-size:12px;line-height:18px;overflow-wrap:anywhere}.dsh-remote-route[data-error] .dsh-remote-route-description{color:var(--dsw-alias-state-error-primary,#dc2626)}.dsh-remote-controls{display:flex;align-items:center;justify-content:flex-end;gap:7px;margin-top:12px}
        .manager-status{margin-top:16px;border:1px solid color-mix(in srgb,var(--dsw-alias-state-business-primary,#2563eb) 26%,var(--dsw-alias-border-l2,#dbe1ea));border-radius:14px;padding:14px;background:color-mix(in srgb,var(--dsw-alias-state-business-primary,#2563eb) 5%,var(--dsw-alias-bg-layer-1,#f1f5f9))}.manager-status[data-kind="error"]{border-color:color-mix(in srgb,var(--dsw-alias-state-error-primary,#dc2626) 55%,var(--dsw-alias-border-l2,#dbe1ea));background:color-mix(in srgb,var(--dsw-alias-state-error-primary,#dc2626) 6%,var(--dsw-alias-bg-layer-1,#f1f5f9))}
        .status-line{display:flex;align-items:flex-start;gap:10px}.status-copy{min-width:0;flex:1}.status-title{font-size:13px;font-weight:650;line-height:20px}.status-detail{margin-top:2px;color:var(--dsw-alias-label-tertiary,#64748b);font-size:12px;line-height:18px}.status-symbol{display:grid;flex:0 0 auto;width:20px;height:20px;place-items:center;border-radius:50%;background:color-mix(in srgb,var(--dsw-alias-state-business-primary,#2563eb) 13%,transparent);color:var(--dsw-alias-state-business-primary,#2563eb);font-size:12px;font-weight:700}.manager-status[data-kind="error"] .status-symbol{background:color-mix(in srgb,var(--dsw-alias-state-error-primary,#dc2626) 13%,transparent);color:var(--dsw-alias-state-error-primary,#dc2626)}
        .progress-steps{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:7px;margin:14px 0 0;padding:0;list-style:none}.progress-steps[data-count="2"]{grid-template-columns:repeat(2,minmax(0,1fr))}.progress-step{position:relative;min-width:0;padding-top:20px;color:var(--dsw-alias-label-tertiary,#64748b);font-size:10px;font-weight:550;line-height:14px}.progress-step::before{position:absolute;z-index:1;top:0;left:0;width:10px;height:10px;border:2px solid var(--dsw-alias-border-l2,#cbd5e1);border-radius:50%;background:var(--dsw-alias-bg-layer-1,#f1f5f9);content:""}.progress-step:not(:last-child)::after{position:absolute;top:5px;right:5px;left:14px;height:1px;background:var(--dsw-alias-border-l2,#cbd5e1);content:""}.progress-step[data-state="done"]{color:var(--dsw-alias-label-secondary,#475569)}.progress-step[data-state="done"]::before{border-color:var(--dsw-alias-state-success-primary,#22a45d);background:var(--dsw-alias-state-success-primary,#22a45d);box-shadow:inset 0 0 0 2px var(--dsw-alias-bg-layer-1,#fff)}.progress-step[data-state="current"]{color:var(--dsw-alias-label-primary,#111827)}.progress-step[data-state="current"]::before{border-color:var(--dsw-alias-state-business-primary,#2563eb);border-top-color:transparent;animation:spin .8s linear infinite}
        .confirm{margin-top:18px;border:1px solid var(--dsw-alias-border-l2,#dbe1ea);border-radius:14px;padding:16px;background:var(--dsw-alias-bg-layer-1,#f1f5f9)}.confirm h3{font-size:14px;line-height:21px}.confirm-body{margin-top:4px;color:var(--dsw-alias-label-tertiary,#64748b);font-size:12px;line-height:18px}.confirm-list{display:grid;gap:7px;margin:14px 0 0;padding:0;list-style:none}.confirm-list li{position:relative;padding-left:18px;color:var(--dsw-alias-label-secondary,#475569);font-size:12px;line-height:18px}.confirm-list li::before{position:absolute;top:7px;left:3px;width:5px;height:5px;border-radius:50%;background:var(--dsw-alias-state-warning-primary,#d97706);content:""}.confirm-actions{display:flex;justify-content:flex-end;gap:8px;margin-top:16px}
        .tailscale-guide{margin-top:16px}.guide-status{border:1px solid color-mix(in srgb,var(--dsw-alias-state-business-primary,#2563eb) 30%,var(--dsw-alias-border-l2,#dbe1ea));border-radius:13px;padding:12px 14px;background:color-mix(in srgb,var(--dsw-alias-state-business-primary,#2563eb) 6%,var(--dsw-alias-bg-layer-1,#f1f5f9))}.guide-status-title{font-size:13px;font-weight:650;line-height:20px}.guide-status-detail{margin-top:2px;color:var(--dsw-alias-label-tertiary,#64748b);font-size:12px;line-height:18px}.guide-steps{display:grid;gap:0;margin:14px 0 0;padding:0;list-style:none}.guide-step{display:grid;grid-template-columns:30px minmax(0,1fr);gap:10px;padding:11px 0;border-bottom:1px solid var(--dsw-alias-border-l2,#dbe1ea)}.guide-step:last-child{border-bottom:0}.guide-step-number{display:grid;width:26px;height:26px;place-items:center;border-radius:8px;background:var(--dsw-alias-bg-layer-1,#f1f5f9);color:var(--dsw-alias-label-secondary,#475569);font-size:11px;font-weight:700}.guide-step-title{font-size:13px;font-weight:650;line-height:20px}.guide-step-detail{margin-top:2px;color:var(--dsw-alias-label-tertiary,#64748b);font-size:12px;line-height:18px}.guide-step-links{display:flex;flex-wrap:wrap;gap:7px;margin-top:8px}.guide-step-links a{border-radius:8px;padding:5px 8px;background:color-mix(in srgb,var(--dsw-alias-state-business-primary,#2563eb) 9%,transparent);color:var(--dsw-alias-state-business-primary,#2563eb);font-size:11px;font-weight:600;text-decoration:none}.guide-step-links a:focus-visible{outline:2px solid var(--dsw-alias-state-business-primary,#2563eb);outline-offset:2px}.guide-safety{margin-top:12px;border-radius:10px;padding:10px 12px;background:color-mix(in srgb,var(--dsw-alias-state-warning-primary,#d97706) 8%,transparent);color:var(--dsw-alias-label-secondary,#475569);font-size:11px;line-height:17px}
        .qr{display:block;width:248px;height:248px;margin:20px auto 16px;border:10px solid #fff;border-radius:14px;background:#fff}.label{margin-top:6px;color:var(--dsw-alias-label-tertiary,#64748b);font-size:11px;text-transform:uppercase;letter-spacing:.06em}.url{margin-top:5px;border-radius:10px;padding:10px 12px;background:var(--dsw-alias-bg-layer-1,#f1f5f9);font:12px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace;overflow-wrap:anywhere}.actions{display:flex;align-items:center;gap:8px;margin-top:18px}.spacer{flex:1}
        button{display:inline-flex;min-height:36px;align-items:center;justify-content:center;gap:7px;border:1px solid var(--dsw-alias-border-l2,#dbe1ea);border-radius:9px;padding:7px 13px;background:transparent;color:inherit;cursor:pointer;font:inherit;font-size:12px;font-weight:600;line-height:18px;transition:transform 100ms ease-out,background-color 120ms ease,color 120ms ease,border-color 120ms ease}button:hover:not(:disabled){background:var(--dsw-alias-interactive-bg-hover,#e9eef5)}button:active:not(:disabled){transform:scale(.97)}button[aria-disabled="true"]:hover{background:transparent}button[aria-disabled="true"]:active{transform:none}button:disabled{cursor:default;opacity:.5}button[data-busy]{cursor:wait;opacity:1}.primary,.dsh-remote-primary{border-color:var(--dsw-alias-label-primary,#172033);background:var(--dsw-alias-label-primary,#172033);color:var(--dsw-alias-bg-layer-3,#fff)}.dsh-remote-danger{border-color:color-mix(in srgb,var(--dsw-alias-state-error-primary,#dc2626) 40%,var(--dsw-alias-border-l2,#dbe1ea));color:var(--dsw-alias-state-error-primary,#dc2626)}.dsh-remote-danger:hover:not(:disabled){background:color-mix(in srgb,var(--dsw-alias-state-error-primary,#dc2626) 8%,transparent)}button:focus-visible{outline:2px solid var(--dsw-alias-state-business-primary,#2563eb);outline-offset:2px}
        .dsh-remote-spinner{display:inline-block;flex:0 0 auto;width:13px;height:13px;border:2px solid color-mix(in srgb,currentColor 28%,transparent);border-top-color:currentColor;border-radius:50%;animation:spin .8s linear infinite}@keyframes spin{to{transform:rotate(360deg)}}@keyframes materialize{from{opacity:0;transform:scale(.985)}to{opacity:1;transform:scale(1)}}@keyframes view-in{from{opacity:0;transform:translateY(3px)}to{opacity:1;transform:translateY(0)}}
        @media(max-width:620px){.chooser-routes{grid-template-columns:1fr}.dsh-remote-route-description{min-height:0}.progress-steps{grid-template-columns:1fr}.progress-step{min-height:22px;padding:2px 0 2px 24px}.progress-step::before{top:5px}.progress-step:not(:last-child)::after{top:17px;bottom:-9px;left:5px;width:1px;height:auto}}
        @media(prefers-reduced-motion:reduce){.dialog,.dialog-view,.dsh-remote-route,button{animation:none;transition:opacity 120ms ease}.dsh-remote-spinner,.progress-step[data-state="current"]::before{animation:none}.progress-step[data-state="current"]::before{border-color:var(--dsw-alias-state-business-primary,#2563eb)}button:active:not(:disabled){transform:none}}
        @media(prefers-reduced-transparency:reduce){.dialog{background:var(--dsw-alias-bg-layer-3,#fff);backdrop-filter:none}}
        @media(prefers-contrast:more){.dialog,.dsh-remote-route,.manager-status,.confirm{border-width:2px}.dsh-remote-route-description,.body,.status-detail{color:var(--dsw-alias-label-secondary,#334155)}}
      </style>
      <div class="backdrop" role="presentation">
        <section class="dialog" role="dialog" aria-modal="true" aria-labelledby="dsh-remote-dialog-title" aria-describedby="dsh-remote-dialog-description">
          <h2 id="dsh-remote-dialog-title" tabindex="-1"></h2>
          <p class="body" id="dsh-remote-dialog-description"></p>
          <div class="manager-status dialog-view" role="status" aria-live="polite" aria-atomic="true" hidden>
            <div class="status-line"><span class="status-symbol" aria-hidden="true"></span><div class="status-copy"><div class="status-title"></div><p class="status-detail"></p></div></div>
            <ol class="progress-steps" hidden></ol>
          </div>
          <div class="chooser dialog-view"><div class="chooser-routes"></div></div>
          <div class="confirm dialog-view" hidden>
            <h3></h3><p class="confirm-body"></p>
            <ul class="confirm-list"><li class="confirm-interrupt"></li><li class="confirm-return"></li></ul>
            <div class="confirm-actions"><button class="confirm-cancel"></button><button class="dsh-remote-primary confirm-enable"></button></div>
          </div>
          <div class="tailscale-guide dialog-view" hidden><div class="guide-status" role="status"><div class="guide-status-title"></div><p class="guide-status-detail"></p></div><ol class="guide-steps"></ol><p class="guide-safety"></p></div>
          <div class="pairing dialog-view" hidden><img class="qr" alt=""><p class="label"></p><div class="url"></div></div>
          <div class="actions"><button class="back" hidden></button><button class="dsh-remote-danger reset" hidden></button><span class="spacer"></span><button class="copy" hidden></button><button class="primary close"></button></div>
        </section>
      </div>
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
    tailscaleGuideButton = tailscale.guideButton
    routes.append(lanRoute, tailscaleRoute)
    layerShadow.querySelector('.confirm-cancel').addEventListener('click', () => {
      if (confirmationAction === 'remote-lan-reset') {
        openPairing(LAN_TRANSPORT)
        return
      }
      openConnectionManager()
      if (!tailscaleActionButton.disabled) tailscaleActionButton.focus()
    })
    layerShadow.querySelector('.confirm-enable').addEventListener('click', () => {
      if (confirmationAction === 'remote-lan-reset') {
        openConnectionManager()
        requestTransportAction('remote-lan-reset', LAN_TRANSPORT)
        return
      }
      renderOperationManager({
        transport: TAILSCALE_TRANSPORT,
        action: 'remote-enable',
        stage: 'checking',
        active: true,
      })
      requestTransportAction('remote-enable', TAILSCALE_TRANSPORT)
    })
    layerShadow.querySelector('.backdrop').addEventListener('click', event => {
      if (event.target === event.currentTarget) closePairing()
    })
    layerShadow.querySelector('.close').addEventListener('click', closePairing)
    layerShadow.querySelector('.copy').addEventListener('click', copyAddress)
    layerShadow.querySelector('.back').addEventListener('click', openConnectionManager)
    layerShadow.querySelector('.reset').addEventListener('click', openLanResetConfirmation)
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
    ;(document.body || document.documentElement).append(layer)
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

  function createGuideLink(label, href) {
    const link = document.createElement('a')
    link.href = href
    link.textContent = label
    return link
  }

  function renderTailscaleGuide() {
    if (!layerShadow) return
    const copy = copyFor(currentLanguage())
    const current = tailscaleGuideState(status, currentLanguage())
    layerShadow.querySelector('.guide-status-title').textContent = current.title
    layerShadow.querySelector('.guide-status-detail').textContent = current.detail

    const steps = [
      {
        title: copy.guideStepMacTitle,
        detail: copy.guideStepMacDetail,
        links: [[copy.guideMacLink, 'https://tailscale.com/download/mac']],
      },
      {
        title: copy.guideStepIPhoneTitle,
        detail: copy.guideStepIPhoneDetail,
        links: [[copy.guideIPhoneLink, 'https://tailscale.com/download/ios']],
      },
      {
        title: copy.guideStepDNSHTitle,
        detail: copy.guideStepDNSDetail,
        links: [[copy.guideDNSLink, 'https://login.tailscale.com/admin/dns']],
      },
      {
        title: copy.guideStepEnableTitle,
        detail: copy.guideStepEnableDetail,
        links: [[copy.guideHelpLink, 'https://tailscale.com/docs/features/tailscale-serve']],
      },
      {
        title: copy.guideStepTestTitle,
        detail: copy.guideStepTestDetail,
        links: [],
      },
    ]
    const items = steps.map((step, index) => {
      const item = document.createElement('li')
      item.className = 'guide-step'
      const number = document.createElement('span')
      number.className = 'guide-step-number'
      number.textContent = String(index + 1)
      number.setAttribute('aria-hidden', 'true')
      const content = document.createElement('div')
      const title = document.createElement('div')
      title.className = 'guide-step-title'
      title.textContent = step.title
      const detail = document.createElement('p')
      detail.className = 'guide-step-detail'
      detail.textContent = step.detail
      content.append(title, detail)
      if (step.links.length) {
        const links = document.createElement('div')
        links.className = 'guide-step-links'
        links.append(...step.links.map(([label, href]) => createGuideLink(label, href)))
        content.append(links)
      }
      item.append(number, content)
      return item
    })
    layerShadow.querySelector('.guide-steps').replaceChildren(...items)
    layerShadow.querySelector('.guide-safety').textContent = copy.guideSafety
  }

  function openTailscaleGuide() {
    const shouldRememberFocus = !layer || layer.hidden
    ensureLayer()
    if (shouldRememberFocus) pairingReturnFocus = document.activeElement
    const copy = copyFor(currentLanguage())
    layerShadow.querySelector('h2').textContent = copy.guideTitle
    layerShadow.querySelector('.body').textContent = copy.guideBody
    showDialogPanel('guide')
    renderTailscaleGuide()
    layerShadow.querySelector('.back').hidden = false
    layerShadow.querySelector('.back').textContent = copy.back
    layerShadow.querySelector('.copy').hidden = true
    layerShadow.querySelector('.close').hidden = false
    layerShadow.querySelector('.close').textContent = copy.managerClose
    layer.hidden = false
    layerShadow.querySelector('h2').focus()
    refreshStatus(true)
  }

  function openTailscaleConfirmation() {
    const shouldRememberFocus = !layer || layer.hidden
    ensureLayer()
    if (shouldRememberFocus) pairingReturnFocus = document.activeElement
    const copy = copyFor(currentLanguage())
    confirmationAction = 'remote-enable'
    layerShadow.querySelector('h2').textContent = copy.connect
    layerShadow.querySelector('.body').textContent = copy.managerBody
    showDialogPanel('confirm')
    layerShadow.querySelector('.confirm h3').textContent = copy.confirmTitle
    layerShadow.querySelector('.confirm-body').textContent = copy.confirmBody
    layerShadow.querySelector('.confirm-interrupt').textContent = copy.confirmInterrupt
    layerShadow.querySelector('.confirm-return').textContent = copy.confirmReturn
    layerShadow.querySelector('.confirm-cancel').textContent = copy.cancel
    const confirmButton = layerShadow.querySelector('.confirm-enable')
    confirmButton.className = 'dsh-remote-primary confirm-enable'
    confirmButton.textContent = copy.restartAndEnable
    layerShadow.querySelector('.back').hidden = true
    layerShadow.querySelector('.copy').hidden = true
    layerShadow.querySelector('.close').hidden = true
    layer.hidden = false
    layerShadow.querySelector('.confirm-cancel').focus()
  }

  function openLanResetConfirmation() {
    ensureLayer()
    const copy = copyFor(currentLanguage())
    confirmationAction = 'remote-lan-reset'
    layerShadow.querySelector('h2').textContent = copy.lanModalTitle
    layerShadow.querySelector('.body').textContent = copy.lanModalBody
    showDialogPanel('confirm')
    layerShadow.querySelector('.confirm h3').textContent = copy.lanResetTitle
    layerShadow.querySelector('.confirm-body').textContent = copy.lanResetBody
    layerShadow.querySelector('.confirm-interrupt').textContent = copy.lanResetRevoke
    layerShadow.querySelector('.confirm-return').textContent = copy.lanResetKeepAddress
    layerShadow.querySelector('.confirm-cancel').textContent = copy.cancel
    const confirmButton = layerShadow.querySelector('.confirm-enable')
    confirmButton.className = 'dsh-remote-danger confirm-enable'
    confirmButton.textContent = copy.lanResetConfirm
    layerShadow.querySelector('.back').hidden = true
    layerShadow.querySelector('.copy').hidden = true
    layerShadow.querySelector('.close').hidden = true
    layer.hidden = false
    layerShadow.querySelector('.confirm-cancel').focus()
  }

  function openConnectionManager() {
    const shouldRememberFocus = !layer || layer.hidden
    ensureLayer()
    if (shouldRememberFocus) pairingReturnFocus = document.activeElement
    const activeOperation = status.operation.active
      && (status.operation.transport === TAILSCALE_TRANSPORT || !status.operation.transport)
    if (activeOperation) {
      renderOperationManager(status.operation)
      refreshStatus(true)
      return
    }
    const copy = copyFor(currentLanguage())
    layerShadow.querySelector('h2').textContent = copy.connect
    layerShadow.querySelector('.body').textContent = copy.managerBody
    showDialogPanel('chooser')
    layerShadow.querySelector('.back').hidden = true
    layerShadow.querySelector('.copy').hidden = true
    layerShadow.querySelector('.close').hidden = false
    layerShadow.querySelector('.close').textContent = copy.managerClose
    layer.hidden = false
    updateSetting()
    let preferredControl = layerShadow.querySelector('h2')
    if (status.statusReady
      && status.lanEnabled
      && !lanPairButton.disabled
      && !lanPairButton.hidden) {
      preferredControl = lanPairButton
    } else if (status.statusReady
      && !lanActionButton.disabled
      && lanActionButton.getAttribute('aria-disabled') !== 'true') {
      preferredControl = lanActionButton
    } else if (status.tailscaleStatusReady
      && status.enabled
      && !tailscalePairButton.disabled
      && !tailscalePairButton.hidden) {
      preferredControl = tailscalePairButton
    } else if (status.tailscaleStatusReady
      && !tailscaleActionButton.disabled
      && tailscaleActionButton.getAttribute('aria-disabled') !== 'true') {
      preferredControl = tailscaleActionButton
    }
    preferredControl.focus()
    refreshStatus(true)
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
    showDialogPanel('pairing')
    layerShadow.querySelector('.qr').src = qrSvg
    layerShadow.querySelector('.qr').alt = title
    layerShadow.querySelector('.label').textContent = copy.address
    layerShadow.querySelector('.url').textContent = endpoint
    layerShadow.querySelector('.copy').textContent = copy.copy
    layerShadow.querySelector('.copy').hidden = lan
    layerShadow.querySelector('.reset').textContent = copy.lanReset
    layerShadow.querySelector('.back').textContent = copy.back
    layerShadow.querySelector('.back').hidden = false
    layerShadow.querySelector('.close').hidden = false
    layerShadow.querySelector('.close').textContent = copy.close
    layer.hidden = false
    layerShadow.querySelector('.close').focus()
  }

  function closePairing() {
    if (!layer || layer.hidden) return
    if (status.operation.active && visibleOperationId === status.operation.id) {
      dismissedOperationId = status.operation.id
    }
    layer.hidden = true
    if (pairingReturnFocus?.isConnected) pairingReturnFocus.focus()
    pairingReturnFocus = null
  }

  function recoverStalledResume() {
    if (!resumeCurtain || operationResumeSettled) return
    clearResumeOperationParameter()
    openConnectionManager()
    const copy = copyFor(currentLanguage())
    renderManagerStatus({
      title: copy.resumeTakingLong,
      detail: copy.resumeTakingLongDetail,
    })
    refreshStatus(true)
  }

  function clearResumeOperationParameter() {
    if (!resumeOperationId || operationResumeSettled) return
    operationResumeSettled = true
    try {
      const nextURL = new URL(location.href)
      nextURL.searchParams.delete(RESUME_OPERATION_PARAMETER)
      history.replaceState(history.state, '', nextURL)
    } catch {
      // The presentation is still acknowledged even if the URL cannot be rewritten.
    }
    resumeCurtain?.remove()
    resumeCurtain = null
    if (resumeRecoveryTimer) window.clearTimeout(resumeRecoveryTimer)
    resumeRecoveryTimer = 0
  }

  function acknowledgePresentedOperation(operationId) {
    if (!operationId || acknowledgedOperationId === operationId) return
    acknowledgedOperationId = operationId
    lastOperationStage.delete(operationId)
    clearResumeOperationParameter()
    try {
      request('remote-presented', { id: operationId })
    } catch {
      // A later status refresh can safely retry the presentation handshake.
      acknowledgedOperationId = ''
    }
  }

  function isTailscaleEnableOperation(value) {
    const operation = normalizeOperation(value)
    const transport = operation.transport || TAILSCALE_TRANSPORT
    const action = operation.action || 'enable'
    return transport === TAILSCALE_TRANSPORT
      && action.includes('enable')
      && !action.includes('disable')
  }

  function isTailscaleOperation(value) {
    const operation = normalizeOperation(value)
    return (operation.transport || TAILSCALE_TRANSPORT) === TAILSCALE_TRANSPORT
      && (operation.action.includes('enable') || operation.action.includes('disable'))
  }

  function reconcileOperationPresentation(nextStatus) {
    const operation = nextStatus.operation
    const progress = operationProgress(operation)
    const resumeMatches = !operationResumeSettled
      && shouldRestoreOperation(resumeOperationId, operation)
    const sameVisibleOperation = Boolean(operation.id) && visibleOperationId === operation.id
    const requestedHere = Boolean(pendingTailscaleAction || tailscaleOperationRequested)
    const shouldPresent = isTailscaleOperation(operation)
      && (resumeMatches || sameVisibleOperation || requestedHere)
    const authoritativeOutcome = authoritativeOperationOutcome(operation, nextStatus)

    if (operationResumeSettled
      && !operation.active
      && operation.id === resumeOperationId
      && acknowledgedOperationId !== operation.id) {
      acknowledgePresentedOperation(operation.id)
      return
    }

    if (authoritativeOutcome && shouldPresent) {
      tailscaleOperationRequested = ''
      visibleOperationId = ''
      if (authoritativeOutcome === 'enable-ready') openPairing(TAILSCALE_TRANSPORT)
      else openConnectionManager()
      if (operation.active) clearResumeOperationParameter()
      else acknowledgePresentedOperation(operation.id)
      return
    }

    if (operation.active && shouldPresent && dismissedOperationId !== operation.id) {
      if (operation.id) visibleOperationId = operation.id
      renderOperationManager(operation, resumeMatches)
      return
    }

    if (!operation.active && shouldPresent) {
      if (shouldDeferTerminalPresentation(resumeOperationId, operation)) {
        // Native only sets this after the rebuilt Harness page accepts navigation.
        // The old document must leave every terminal outcome and acknowledgement to it.
        return
      }
      if (dismissedOperationId === operation.id) {
        tailscaleOperationRequested = ''
        acknowledgePresentedOperation(operation.id)
        return
      }
      if (operation.error || progress.terminal === 'error') {
        tailscaleOperationRequested = ''
        renderOperationManager(operation, resumeMatches)
        acknowledgePresentedOperation(operation.id)
        return
      }
      if (progress.terminal === 'ready' && isDisableOperation(operation)) {
        tailscaleOperationRequested = ''
        openConnectionManager()
        acknowledgePresentedOperation(operation.id)
        return
      }
      if (isTailscaleEnableOperation(operation)
        && (progress.terminal === 'ready' || nextStatus.enabled)
        && nextStatus.qrSvg) {
        tailscaleOperationRequested = ''
        openPairing(TAILSCALE_TRANSPORT)
        acknowledgePresentedOperation(operation.id)
        return
      }
    }

    if (resumeOperationId
      && !operationResumeSettled
      && nextStatus.statusReady
      && !resumeMatches
      && !operation.active) {
      openConnectionManager()
      const copy = copyFor(currentLanguage())
      renderManagerStatus({
        title: copy.operationErrorTitle,
        detail: copy.resumeMissing,
        kind: 'error',
      })
      acknowledgePresentedOperation(resumeOperationId)
    }
  }

  function publish(next) {
    const previousStatus = status
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
    if (shouldAutoOpenLanPairing(lanAutoPairRequested, previousStatus, status)) {
      lanAutoPairRequested = false
      openPairing(LAN_TRANSPORT)
    }
    reconcileOperationPresentation(status)
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
      updateResumeCurtainCopy()
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
    const surfaceVisible = Boolean(settingRow?.isConnected)
      || Boolean(layer && !layer.hidden)
      || Boolean(resumeCurtain?.isConnected)
    if (!shouldPollStatus(
      status,
      surfaceVisible,
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
    if (resumeOperationId && !resumeCurtain) {
      resumeCurtain = createResumeCurtain(resumeOperationId)
      armResumeRecoveryTimer()
    }
    updateResumeCurtainCopy()
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
      const transport = detail.payload?.transport === LAN_TRANSPORT
        ? LAN_TRANSPORT
        : detail.payload?.transport === TAILSCALE_TRANSPORT
          ? TAILSCALE_TRANSPORT
          : lastActionTransport
      clearPendingAction(transport)
      if (transport === LAN_TRANSPORT) lanAutoPairRequested = false
      publish(statusAfterError(status, transport, message))
    }
  })

  if (document.body) start()
  else document.addEventListener('DOMContentLoaded', start, { once: true })
})()
