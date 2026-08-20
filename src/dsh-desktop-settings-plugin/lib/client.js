window.__ModuleLoader__.load({
  id: 'dsh-desktop-settings-plugin',
  factory: require => {
    const module = { exports: {} }
    const exports = module.exports
    Object.defineProperty(exports, Symbol.toStringTag, { value: 'Module' })

    const React = require('react')
    const NS = 'settings.desktopPlugins'
    const BRIDGE_KEY = '__DSH_DESKTOP_PLUGIN_MANAGER__'
    const RUNTIME_KEY = '__DSH_DESKTOP_RUNTIME__'
    const RUNTIME_EVENT = 'dsh-desktop-runtime'
    const CODEX_PACKAGE = '@deepseek-ai/dsh-subagent-codex'
    const CODEX_PRESET = 'desktop-codex'
    const CLAUDE_CODE_PACKAGE = '@deepseek-ai/dsh-subagent-claude-code'
    const CLAUDE_CODE_PRESET = 'desktop-claude-code'
    const PRODUCT_SUBAGENTS = [
      { key: 'codex', statusKey: 'codex', packageName: CODEX_PACKAGE, presetId: CODEX_PRESET, mark: 'CX', configureAction: 'configure-codex-preset' },
      { key: 'claude', statusKey: 'claudeCode', packageName: CLAUDE_CODE_PACKAGE, presetId: CLAUDE_CODE_PRESET, mark: 'CC', configureAction: 'configure-claude-code-preset' }
    ]
    const inject = ['slots', 'locale', 'connection']

    const en = {
      tab: 'Install & manage',
      intro: 'Install community plugins into the web profile and review changes before restarting DSH.',
      pendingTitle: 'Restart required',
      pendingBody: '{name} is waiting for a restart. Running tasks will be interrupted.',
      restart: 'Restart DSH',
      installing: 'Installing plugin…',
      removing: 'Removing plugin…',
      restarting: 'Restarting DSH…',
      installTitle: 'Install plugin',
      installLabel: 'npm package, public GitHub URL, or dsh install command',
      installPlaceholder: 'For example github:owner/repo, or paste the full dsh command',
      installHint: 'You can paste a full dsh plugin --profile web add command. Desktop uses its bundled DSH and pnpm.',
      install: 'Install',
      installedTitle: 'User-installed plugins',
      installedEmpty: 'No user plugins are installed in the web profile.',
      enabled: 'Enabled',
      inactive: 'Not in bundle',
      source: 'Source',
      remove: 'Remove',
      confirmRemove: 'Remove after restart?',
      cancel: 'Cancel',
      codexTitle: 'Codex subagent',
      codexIntro: 'Install Codex only when you need a separate coding agent. DSH starts one ephemeral Codex thread for each delegated task.',
      codexBundle: 'Runtime bundle',
      codexBundleHint: 'Downloads the official platform-specific Codex runtime. Native Codex sign-in and settings remain authoritative.',
      codexPreset: 'Agent preset',
      codexPresetHint: 'Creates a Standard + Codex preset. New sessions can then expose the subagent_codex tool.',
      codexNotInstalled: 'Not installed',
      codexInstalled: 'Installed',
      codexRestartRequired: 'Restart required',
      codexPresetReady: 'Preset ready',
      codexReady: 'Default for new sessions',
      codexInstall: 'Install Codex',
      codexConfigure: 'Create preset',
      codexUseDefault: 'Use by default',
      codexInstalling: 'Installing Codex…',
      codexConfiguring: 'Creating Codex preset…',
      codexSelecting: 'Updating default preset…',
      codexPermission: 'The installed provider uses Codex approval mode never and the native sandbox. Advanced provider modes remain in the web profile configuration.',
      claudeTitle: 'Claude Code subagent',
      claudeIntro: 'Install Claude Code only when you need a separate coding agent. DSH starts one non-persisted Claude Code query for each delegated task.',
      claudeBundle: 'Runtime bundle',
      claudeBundleHint: 'Downloads the official platform-specific Claude Code runtime. Native Claude settings and sign-in remain authoritative.',
      claudePreset: 'Agent preset',
      claudePresetHint: 'Creates a Standard + Claude Code preset. New sessions can then expose the subagent_claude_code tool.',
      claudeNotInstalled: 'Not installed',
      claudeInstalled: 'Installed',
      claudeRestartRequired: 'Restart required',
      claudePresetReady: 'Preset ready',
      claudeReady: 'Default for new sessions',
      claudeInstall: 'Install Claude Code',
      claudeConfigure: 'Create preset',
      claudeUseDefault: 'Use by default',
      claudeInstalling: 'Installing Claude Code…',
      claudeConfiguring: 'Creating Claude Code preset…',
      claudeSelecting: 'Updating default preset…',
      claudePermission: 'The installed provider uses Claude Code permission mode dontAsk. Advanced provider modes remain in the web profile configuration.',
      cliTitle: 'Command-line integration',
      cliManaged: 'The Desktop dsh command is enabled and shares this web profile.',
      cliManagedRestart: 'The Desktop dsh command is enabled. Open a new Terminal window to use it with this web profile.',
      cliConflict: 'Another dsh command is currently active. Desktop will not replace it silently.',
      cliDisabled: 'Enable the Desktop-bundled dsh command to install plugins from Terminal with the same profile.',
      cliUnavailable: 'The Desktop package does not contain the dsh command launcher.',
      enableCli: 'Enable in Terminal',
      replaceCli: 'Use Desktop dsh',
      removeCli: 'Remove command',
      loading: 'Reading Desktop plugin status…',
      profile: 'Profile: {path}'
    }

    const zh = {
      tab: '安装与管理',
      intro: '把社区插件安装到 web profile，并在重启 DSH 前检查本次变更。',
      pendingTitle: '需要重启',
      pendingBody: '{name} 正在等待重启；正在运行的任务会被中断。',
      restart: '重启 DSH',
      installing: '正在安装插件…',
      removing: '正在移除插件…',
      restarting: '正在重启 DSH…',
      installTitle: '安装插件',
      installLabel: 'npm 包、公开 GitHub 地址或 dsh 安装命令',
      installPlaceholder: '例如 github:owner/repo，或粘贴完整 dsh 命令',
      installHint: '可直接粘贴 dsh plugin --profile web add 完整命令；安装使用桌面版内置的 DSH 和 pnpm。',
      install: '安装',
      installedTitle: '用户安装的插件',
      installedEmpty: '当前 web profile 还没有用户插件。',
      enabled: '已启用',
      inactive: '未加入 Bundle',
      source: '来源',
      remove: '移除',
      confirmRemove: '确认移除？重启后生效',
      cancel: '取消',
      codexTitle: 'Codex 子代理',
      codexIntro: '只在需要独立编码 Agent 时安装 Codex。每次调度都会启动一个临时 Codex thread。',
      codexBundle: '运行时 Bundle',
      codexBundleHint: '按当前平台下载官方 Codex 运行时，继续使用本机 Codex 的登录状态与配置。',
      codexPreset: 'Agent 预设',
      codexPresetHint: '创建“Standard + Codex”预设，让新会话可以使用 subagent_codex 工具。',
      codexNotInstalled: '尚未安装',
      codexInstalled: '已安装',
      codexRestartRequired: '需要重启',
      codexPresetReady: '预设已就绪',
      codexReady: '新会话默认使用',
      codexInstall: '安装 Codex',
      codexConfigure: '创建预设',
      codexUseDefault: '设为默认',
      codexInstalling: '正在安装 Codex…',
      codexConfiguring: '正在创建 Codex 预设…',
      codexSelecting: '正在更新默认预设…',
      codexPermission: '安装后的 provider 默认使用 Codex 的 never 批准模式和原生沙箱。高级模式继续在 web profile 配置中管理。',
      claudeTitle: 'Claude Code 子代理',
      claudeIntro: '只在需要独立编码 Agent 时安装 Claude Code。每次调度都会启动一个不保留会话的 Claude Code query。',
      claudeBundle: '运行时 Bundle',
      claudeBundleHint: '按当前平台下载官方 Claude Code 运行时，继续使用本机 Claude 的登录状态与配置。',
      claudePreset: 'Agent 预设',
      claudePresetHint: '创建“Standard + Claude Code”预设，让新会话可以使用 subagent_claude_code 工具。',
      claudeNotInstalled: '尚未安装',
      claudeInstalled: '已安装',
      claudeRestartRequired: '需要重启',
      claudePresetReady: '预设已就绪',
      claudeReady: '新会话默认使用',
      claudeInstall: '安装 Claude Code',
      claudeConfigure: '创建预设',
      claudeUseDefault: '设为默认',
      claudeInstalling: '正在安装 Claude Code…',
      claudeConfiguring: '正在创建 Claude Code 预设…',
      claudeSelecting: '正在更新默认预设…',
      claudePermission: '安装后的 provider 默认使用 Claude Code 的 dontAsk 权限模式。高级模式继续在 web profile 配置中管理。',
      cliTitle: '命令行集成',
      cliManaged: '桌面版 dsh 命令已启用，并与这里共享同一个 web profile。',
      cliManagedRestart: '桌面版 dsh 命令已启用；请新开一个终端窗口，再使用与这里共享的 web profile。',
      cliConflict: '当前存在另一套 dsh 命令；桌面版不会静默覆盖。',
      cliDisabled: '启用桌面版内置 dsh 后，可以在终端安装插件并同步到这里。',
      cliUnavailable: '当前桌面安装包缺少 dsh 命令启动器。',
      enableCli: '在终端启用',
      replaceCli: '改用桌面版 dsh',
      removeCli: '移除命令',
      loading: '正在读取桌面插件状态…',
      profile: 'Profile：{path}'
    }

    const css = `
      .dpm-root{width:100%;max-width:760px;color:var(--dsw-alias-label-primary);display:flex;flex-direction:column;gap:14px}
      .dpm-root *{box-sizing:border-box}.dpm-root p,.dpm-root h3{margin:0}
      .dpm-intro{color:var(--dsw-alias-label-tertiary);font-size:13px;line-height:20px}
      .dpm-panel{border:1px solid var(--dsw-alias-border-l2);background:var(--dsw-alias-bg-layer-3);border-radius:12px;padding:16px}
      .dpm-panel-head{display:flex;align-items:flex-start;justify-content:space-between;gap:12px;margin-bottom:13px}
      .dpm-panel h3{font-size:14px;font-weight:600;line-height:20px}.dpm-subtle{color:var(--dsw-alias-label-tertiary);font-size:12px;line-height:18px}
      .dpm-pending{border-color:color-mix(in srgb,var(--dsw-alias-state-business-primary) 34%,var(--dsw-alias-border-l2));background:color-mix(in srgb,var(--dsw-alias-state-business-primary) 6%,var(--dsw-alias-bg-layer-3));display:flex;align-items:center;gap:14px}
      .dpm-pending-copy{min-width:0;flex:1}.dpm-pending-copy strong{display:block;font-size:13px}.dpm-pending-copy span{display:block;margin-top:2px;color:var(--dsw-alias-label-secondary);font-size:12px;line-height:18px}
      .dpm-form{display:grid;gap:11px}.dpm-label{display:block;font-size:12px;font-weight:600;line-height:18px}
      .dpm-input-row{display:flex;gap:8px}.dpm-input{min-width:0;flex:1;height:36px;border:1px solid var(--dsw-alias-border-l2);background:var(--dsw-alias-bg-layer-1);color:var(--dsw-alias-label-primary);border-radius:8px;padding:0 11px;font:inherit;font-size:13px;outline:none}
      .dpm-input:focus-visible{border-color:var(--dsw-alias-state-business-primary);box-shadow:0 0 0 2px color-mix(in srgb,var(--dsw-alias-state-business-primary) 18%,transparent)}
      .dpm-button{appearance:none;min-height:34px;border:1px solid var(--dsw-alias-border-l2);background:transparent;color:var(--dsw-alias-label-secondary);border-radius:8px;padding:6px 12px;font:inherit;font-size:12px;font-weight:600;cursor:pointer;white-space:nowrap}
      .dpm-button:hover:not(:disabled){border-color:var(--dsw-alias-label-dimmed);color:var(--dsw-alias-label-primary);background:var(--dsw-alias-interactive-bg-hover)}
      .dpm-button:focus-visible{outline:2px solid var(--dsw-alias-state-business-primary);outline-offset:2px}.dpm-button:disabled{opacity:.45;cursor:default}
      .dpm-primary{border-color:var(--dsw-alias-label-primary);background:var(--dsw-alias-label-primary);color:var(--dsw-alias-bg-layer-3)}.dpm-primary:hover:not(:disabled){background:var(--dsw-alias-label-primary);color:var(--dsw-alias-bg-layer-3)}
      .dpm-danger{color:var(--dsw-alias-state-error-primary)}
      .dpm-status{min-height:18px;color:var(--dsw-alias-label-tertiary);font-size:12px;line-height:18px;white-space:pre-wrap}.dpm-status[data-error=true]{color:var(--dsw-alias-state-error-primary)}
      .dpm-list{list-style:none;margin:0;padding:0;display:grid;gap:8px}.dpm-plugin{border-top:1px solid var(--dsw-alias-border-l2);padding-top:12px;display:flex;align-items:flex-start;gap:12px}.dpm-plugin:first-child{border-top:0;padding-top:0}
      .dpm-plugin-copy{min-width:0;flex:1}.dpm-name-row{display:flex;align-items:center;gap:8px}.dpm-name{font-size:13px;font-weight:600;line-height:20px;overflow-wrap:anywhere}
      .dpm-tag{border-radius:5px;padding:1px 6px;font-size:11px;line-height:16px;color:var(--dsw-alias-label-secondary);background:var(--dsw-alias-bg-layer-1)}.dpm-tag[data-active=true]{color:var(--dsw-alias-state-success-primary);background:color-mix(in srgb,var(--dsw-alias-state-success-primary) 10%,transparent)}
      .dpm-spec{margin-top:3px!important;color:var(--dsw-alias-label-tertiary);font-family:var(--ds-font-family-code);font-size:11px;line-height:17px;overflow-wrap:anywhere}
      .dpm-actions{display:flex;align-items:center;gap:6px}.dpm-cli{display:flex;align-items:center;gap:14px}.dpm-cli-copy{min-width:0;flex:1}.dpm-cli-copy h3{margin-bottom:3px}
      .dpm-profile{margin-top:7px!important;color:var(--dsw-alias-label-tertiary);font-family:var(--ds-font-family-code);font-size:10px;line-height:16px;overflow-wrap:anywhere}
      .dpm-codex-head{display:flex;align-items:flex-start;gap:11px}.dpm-codex-mark{flex:none;width:30px;height:30px;border:1px solid var(--dsw-alias-border-l2);border-radius:8px;display:grid;place-items:center;color:var(--dsw-alias-label-secondary);background:var(--dsw-alias-bg-layer-1);font-size:10px;font-weight:700;letter-spacing:.04em}
      .dpm-codex-copy{min-width:0;flex:1}.dpm-codex-copy h3{margin-bottom:2px}.dpm-codex-rows{margin-top:14px;border-top:1px solid var(--dsw-alias-border-l2)}.dpm-codex-row{display:flex;align-items:center;gap:14px;padding:12px 0;border-bottom:1px solid var(--dsw-alias-border-l2)}
      .dpm-codex-row-copy{min-width:0;flex:1}.dpm-codex-row-copy strong{display:block;font-size:12px;line-height:18px}.dpm-codex-row-copy p{margin-top:2px!important}.dpm-codex-row-action{display:flex;align-items:center;gap:8px;flex:none}.dpm-codex-note{margin-top:11px!important;color:var(--dsw-alias-label-tertiary);font-size:11px;line-height:17px}
      .dpm-runtime{box-sizing:border-box;width:100%;min-width:0;height:28px;padding:0 8px;color:var(--dsw-alias-label-tertiary);font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;font-size:11.5px;font-weight:400;line-height:28px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;user-select:none}
      .dpm-runtime[data-wide=false]{width:36px;height:30px;padding:0;text-align:center;font-size:10px;font-weight:600;line-height:30px;user-select:none}
      @media(max-width:620px){.dpm-input-row,.dpm-cli,.dpm-pending,.dpm-codex-row{align-items:stretch;flex-direction:column}.dpm-input-row .dpm-button{width:100%}.dpm-plugin{flex-direction:column}.dpm-actions,.dpm-codex-row-action{width:100%;justify-content:flex-end}}
    `

    if (typeof document !== 'undefined' && !document.querySelector('style[data-plugin-css="dsh-desktop-settings-plugin"]')) {
      const style = document.createElement('style')
      style.dataset.plugin = 'dsh-desktop-settings-plugin'
      style.dataset.pluginCss = 'dsh-desktop-settings-plugin'
      style.textContent = css
      document.head.appendChild(style)
    }

    function template(t, key, values) {
      let text = t(key)
      for (const [name, value] of Object.entries(values || {})) text = text.replace(`{${name}}`, String(value))
      return text
    }

    function pendingName(pending) {
      return pending?.changes?.[0]?.name || pending?.packages?.[0] || pending?.spec || 'Plugin change'
    }

    function ProductSubagentPanel({ t, product, view, hostStatus, pending, busy }) {
      const copy = suffix => t(`${product.key}${suffix}`)
      const productStatus = view.status
      const action = view.action
      return React.createElement('section', { className: 'dpm-panel', 'aria-labelledby': `dpm-${product.key}-title` },
        React.createElement('div', { className: 'dpm-codex-head' },
          React.createElement('div', { className: 'dpm-codex-mark', 'aria-hidden': 'true' }, product.mark),
          React.createElement('div', { className: 'dpm-codex-copy' },
            React.createElement('h3', { id: `dpm-${product.key}-title` }, copy('Title')),
            React.createElement('p', { className: 'dpm-subtle' }, copy('Intro'))
          ),
          React.createElement('span', { className: 'dpm-tag', 'data-active': view.stageActive ? 'true' : undefined }, view.isDefault ? copy('Ready') : view.stage)
        ),
        React.createElement('div', { className: 'dpm-codex-rows' },
          React.createElement('div', { className: 'dpm-codex-row' },
            React.createElement('div', { className: 'dpm-codex-row-copy' },
              React.createElement('strong', null, copy('Bundle')),
              React.createElement('p', { className: 'dpm-subtle' }, copy('BundleHint'))
            ),
            React.createElement('div', { className: 'dpm-codex-row-action' },
              React.createElement('span', { className: 'dpm-tag', 'data-active': productStatus?.active && !pending ? 'true' : undefined }, productStatus?.installed ? (pending ? copy('RestartRequired') : copy('Installed')) : copy('NotInstalled')),
              action && !productStatus?.installed ? React.createElement('button', {
                type: 'button', className: `dpm-button${action.primary ? ' dpm-primary' : ''}`,
                disabled: !hostStatus || busy || view.selecting || Boolean(pending), onClick: action.run
              }, action.label) : null
            )
          ),
          React.createElement('div', { className: 'dpm-codex-row' },
            React.createElement('div', { className: 'dpm-codex-row-copy' },
              React.createElement('strong', null, copy('Preset')),
              React.createElement('p', { className: 'dpm-subtle' }, copy('PresetHint'))
            ),
            React.createElement('div', { className: 'dpm-codex-row-action' },
              React.createElement('span', { className: 'dpm-tag', 'data-active': productStatus?.presetReady ? 'true' : undefined }, view.isDefault ? copy('Ready') : productStatus?.presetReady ? copy('PresetReady') : copy('NotInstalled')),
              action && productStatus?.installed && !pending ? React.createElement('button', {
                type: 'button', className: `dpm-button${action.primary ? ' dpm-primary' : ''}`, disabled: busy || view.selecting,
                onClick: action.run
              }, view.selecting ? copy('Selecting') : action.label) : null
            )
          )
        ),
        React.createElement('p', { className: 'dpm-codex-note' }, copy('Permission')),
        React.createElement('p', {
          className: 'dpm-status', role: view.error ? 'alert' : 'status',
          'data-error': view.error ? 'true' : undefined
        }, view.error || (view.isInstalling ? copy('Installing') : view.operationText))
      )
    }

    function DesktopPluginManagerTab({ t, api }) {
      const bridge = window[BRIDGE_KEY]
      const [spec, setSpec] = React.useState('')
      const [confirmRemove, setConfirmRemove] = React.useState('')
      const [productDefaults, setProductDefaults] = React.useState({})
      const [selectingProduct, setSelectingProduct] = React.useState('')
      const [installingProduct, setInstallingProduct] = React.useState('')
      const [productErrors, setProductErrors] = React.useState({})
      const empty = React.useMemo(() => ({ status: null, busyOperation: '', error: '' }), [])
      const state = React.useSyncExternalStore(
        bridge?.subscribe || (() => () => {}),
        bridge?.getSnapshot || (() => empty),
        () => empty
      )
      const status = state.status
      const busy = Boolean(state.busyOperation)
      const pending = status?.pending
      const installed = status?.installed || []
      const readyPresetSignature = PRODUCT_SUBAGENTS
        .filter(product => status?.[product.statusKey]?.presetReady)
        .map(product => product.presetId)
        .join('|')

      React.useEffect(() => {
        bridge?.request('status')
      }, [bridge])

      const loadProductDefaults = React.useCallback(async () => {
        if (!api || !readyPresetSignature) {
          setProductDefaults({})
          return
        }
        try {
          const response = await api.agentPresets.list({})
          if (!response.result.ok) throw new Error(response.result.error.message)
          setProductDefaults(Object.fromEntries(PRODUCT_SUBAGENTS.map(product => [
            product.key,
            Boolean(response.result.value.presets.find(preset => preset.id === product.presetId)?.isDefault)
          ])))
          setProductErrors({})
        } catch (error) {
          const message = error instanceof Error ? error.message : String(error)
          setProductErrors(Object.fromEntries(PRODUCT_SUBAGENTS.map(product => [product.key, message])))
        }
      }, [api, readyPresetSignature])

      React.useEffect(() => {
        loadProductDefaults()
      }, [loadProductDefaults])

      React.useEffect(() => {
        if (!state.busyOperation) setInstallingProduct('')
      }, [state.busyOperation])

      const submit = event => {
        event.preventDefault()
        const value = spec.trim()
        if (!value || busy || pending) return
        bridge?.request('install-plugin', { spec: value })
      }

      const remove = name => {
        if (confirmRemove !== name) {
          setConfirmRemove(name)
          return
        }
        setConfirmRemove('')
        bridge?.request('remove-plugin', { name })
      }

      const useProductByDefault = async product => {
        const productStatus = status?.[product.statusKey]
        if (!api || !productStatus?.presetReady || selectingProduct) return
        setSelectingProduct(product.key)
        setProductErrors(current => ({ ...current, [product.key]: '' }))
        try {
          const response = await api.settings.update({
            ns: 'agent-presets',
            patch: { default: product.presetId }
          })
          if (!response.result.ok) throw new Error(response.result.error.message)
          await loadProductDefaults()
        } catch (error) {
          setProductErrors(current => ({
            ...current,
            [product.key]: error instanceof Error ? error.message : String(error)
          }))
        } finally {
          setSelectingProduct('')
        }
      }

      const operationText = state.busyOperation === 'install-plugin'
        ? t('installing')
        : state.busyOperation === 'remove-plugin'
          ? t('removing')
          : state.busyOperation === 'restart-harness'
            ? t('restarting')
            : ''

      const productViews = PRODUCT_SUBAGENTS.map(product => {
        const productStatus = status?.[product.statusKey] || null
        const copy = suffix => t(`${product.key}${suffix}`)
        const isDefault = Boolean(productDefaults[product.key])
        let stage = copy('NotInstalled')
        let stageActive = false
        let action = null
        if (productStatus?.installed) {
          stage = pending ? copy('RestartRequired') : productStatus.presetReady ? copy('PresetReady') : copy('Installed')
          stageActive = Boolean(productStatus.active && !pending)
        }
        if (!productStatus?.installed) {
          action = {
            label: copy('Install'),
            primary: true,
            run: () => {
              setInstallingProduct(product.key)
              bridge?.request('install-plugin', { spec: productStatus?.bundleSpec || product.packageName })
            }
          }
        } else if (!pending && productStatus.active && !productStatus.presetReady) {
          action = {
            label: copy('Configure'),
            primary: true,
            run: () => bridge?.request(product.configureAction)
          }
        } else if (!pending && productStatus.presetReady && !isDefault) {
          action = {
            label: copy('UseDefault'),
            primary: false,
            run: () => useProductByDefault(product)
          }
        }
        return {
          product,
          status: productStatus,
          stage,
          stageActive,
          isDefault,
          action,
          selecting: selectingProduct === product.key,
          isInstalling: installingProduct === product.key,
          error: state.error || productErrors[product.key] || '',
          operationText: state.busyOperation === product.configureAction ? copy('Configuring') : operationText
        }
      })

      let cliText = t('cliDisabled')
      let cliLabel = t('enableCli')
      let cliAction = 'install-cli'
      let cliValues = {}
      if (!status?.cli?.bundledReady) {
        cliText = t('cliUnavailable')
        cliLabel = ''
      } else if (status.cli.managed) {
        cliText = t(status.cli.requiresNewTerminal ? 'cliManagedRestart' : 'cliManaged')
        cliLabel = t('removeCli')
        cliAction = 'remove-cli'
      } else if (status.cli.conflict) {
        cliText = t('cliConflict')
        cliLabel = t('replaceCli')
        cliValues = { replace: '1' }
      }

      return React.createElement('div', { className: 'dpm-root' },
        React.createElement('p', { className: 'dpm-intro' }, t('intro')),
        pending ? React.createElement('section', { className: 'dpm-panel dpm-pending', 'aria-live': 'polite' },
          React.createElement('div', { className: 'dpm-pending-copy' },
            React.createElement('strong', null, t('pendingTitle')),
            React.createElement('span', null, template(t, 'pendingBody', { name: pendingName(pending) }))
          ),
          React.createElement('button', {
            type: 'button', className: 'dpm-button dpm-primary', disabled: busy,
            onClick: () => bridge?.request('restart-harness')
          }, t('restart'))
        ) : null,
        bridge ? productViews.map(view => React.createElement(ProductSubagentPanel, {
          key: view.product.key,
          t,
          product: view.product,
          view,
          hostStatus: status,
          pending,
          busy
        })) : null,
        React.createElement('section', { className: 'dpm-panel', 'aria-labelledby': 'dpm-install-title' },
          React.createElement('div', { className: 'dpm-panel-head' },
            React.createElement('div', null,
              React.createElement('h3', { id: 'dpm-install-title' }, t('installTitle')),
              React.createElement('p', { className: 'dpm-subtle' }, t('installHint'))
            )
          ),
          React.createElement('form', { className: 'dpm-form', onSubmit: submit },
            React.createElement('label', { className: 'dpm-label', htmlFor: 'dpm-plugin-spec' }, t('installLabel')),
            React.createElement('div', { className: 'dpm-input-row' },
              React.createElement('input', {
                id: 'dpm-plugin-spec', className: 'dpm-input', type: 'text', autoComplete: 'off', spellCheck: false,
                value: spec, placeholder: t('installPlaceholder'), disabled: busy || Boolean(pending),
                onChange: event => setSpec(event.currentTarget.value)
              }),
              React.createElement('button', {
                className: 'dpm-button dpm-primary', type: 'submit',
                disabled: busy || Boolean(pending) || !spec.trim()
              }, t('install'))
            ),
            React.createElement('p', {
              className: 'dpm-status', role: state.error ? 'alert' : 'status',
              'data-error': state.error ? 'true' : undefined
            }, state.error || operationText)
          )
        ),
        React.createElement('section', { className: 'dpm-panel', 'aria-labelledby': 'dpm-installed-title' },
          React.createElement('div', { className: 'dpm-panel-head' },
            React.createElement('h3', { id: 'dpm-installed-title' }, t('installedTitle'))
          ),
          !status ? React.createElement('p', { className: 'dpm-subtle' }, t('loading'))
            : installed.length === 0 ? React.createElement('p', { className: 'dpm-subtle' }, t('installedEmpty'))
              : React.createElement('ul', { className: 'dpm-list' }, installed.map(plugin =>
                React.createElement('li', { className: 'dpm-plugin', key: plugin.name },
                  React.createElement('div', { className: 'dpm-plugin-copy' },
                    React.createElement('div', { className: 'dpm-name-row' },
                      React.createElement('strong', { className: 'dpm-name' }, plugin.name),
                      React.createElement('span', { className: 'dpm-tag', 'data-active': plugin.active ? 'true' : undefined }, plugin.active ? t('enabled') : t('inactive'))
                    ),
                    React.createElement('p', { className: 'dpm-spec' }, `${t('source')}: ${plugin.spec}`)
                  ),
                  React.createElement('div', { className: 'dpm-actions' },
                    confirmRemove === plugin.name ? React.createElement('button', {
                      type: 'button', className: 'dpm-button', onClick: () => setConfirmRemove('')
                    }, t('cancel')) : null,
                    React.createElement('button', {
                      type: 'button', className: 'dpm-button dpm-danger', disabled: busy || Boolean(pending),
                      onClick: () => remove(plugin.name)
                    }, confirmRemove === plugin.name ? t('confirmRemove') : t('remove'))
                  )
                )
              ))
        ),
        React.createElement('section', { className: 'dpm-panel dpm-cli', 'aria-labelledby': 'dpm-cli-title' },
          React.createElement('div', { className: 'dpm-cli-copy' },
            React.createElement('h3', { id: 'dpm-cli-title' }, t('cliTitle')),
            React.createElement('p', { className: 'dpm-subtle' }, cliText),
            status?.profilePath ? React.createElement('p', { className: 'dpm-profile' }, template(t, 'profile', { path: status.profilePath })) : null
          ),
          cliLabel ? React.createElement('button', {
            type: 'button', className: 'dpm-button', disabled: busy,
            onClick: () => bridge?.request(cliAction, cliValues)
          }, cliLabel) : null
        )
      )
    }

    function DesktopRuntimeStatus({ wide }) {
      const [runtime, setRuntime] = React.useState(() => window[RUNTIME_KEY] || null)
      React.useEffect(() => {
        const sync = event => setRuntime(event.detail || window[RUNTIME_KEY] || null)
        window.addEventListener(RUNTIME_EVENT, sync)
        return () => window.removeEventListener(RUNTIME_EVENT, sync)
      }, [])
      if (!runtime) return null
      return React.createElement('div', {
        className: 'dpm-runtime',
        'data-wide': String(Boolean(wide)),
        role: 'status',
        'aria-label': runtime.label,
        title: runtime.label
      }, wide ? runtime.label : runtime.harnessVersion)
    }

    function apply(ctx) {
      ctx.effect(() => ctx.locale.register(NS, { zh, en }), 'desktop plugin manager dictionaries')
      const t = ctx.locale.bind(NS)
      const { api } = ctx.get('connection')
      ctx.slots.inject('settings.plugins.tab', () => ctx.slots.register({
        name: 'settings.plugins.tab',
        id: 'desktop-manager',
        order: -10,
        label: () => t('tab'),
        locale: NS
      }, props => React.createElement(DesktopPluginManagerTab, { ...props, api })))
      ctx.slots.inject('sidebar.footer.action', () => ctx.slots.register({
        name: 'sidebar.footer.action',
        id: 'desktop-runtime',
        order: 10
      }, DesktopRuntimeStatus))
    }

    exports.NS = NS
    exports.apply = apply
    exports.inject = inject
    return module.exports
  }
})
