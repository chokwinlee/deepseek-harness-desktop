window.__ModuleLoader__.load({
  id: 'dsh-desktop-settings-plugin',
  factory: require => {
    const module = { exports: {} }
    const exports = module.exports
    Object.defineProperty(exports, Symbol.toStringTag, { value: 'Module' })

    const React = require('react')
    const NS = 'settings.desktopPlugins'
    const BRIDGE_KEY = '__DSH_DESKTOP_PLUGIN_MANAGER__'
    const inject = ['slots', 'locale']

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
      installLabel: 'npm package or public GitHub URL',
      installPlaceholder: 'For example dsh-daily-review',
      installHint: 'The Desktop-bundled DSH and pnpm are used; a separate DSH installation is not required.',
      install: 'Install',
      installedTitle: 'User-installed plugins',
      installedEmpty: 'No user plugins are installed in the web profile.',
      enabled: 'Enabled',
      inactive: 'Not in bundle',
      source: 'Source',
      remove: 'Remove',
      confirmRemove: 'Remove after restart?',
      cancel: 'Cancel',
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
      installLabel: 'npm 包或公开 GitHub 地址',
      installPlaceholder: '例如 dsh-daily-review',
      installHint: '使用桌面版内置的 DSH 和 pnpm，不要求用户另外安装 DSH。',
      install: '安装',
      installedTitle: '用户安装的插件',
      installedEmpty: '当前 web profile 还没有用户插件。',
      enabled: '已启用',
      inactive: '未加入 Bundle',
      source: '来源',
      remove: '移除',
      confirmRemove: '确认移除？重启后生效',
      cancel: '取消',
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
      @media(max-width:620px){.dpm-input-row,.dpm-cli,.dpm-pending{align-items:stretch;flex-direction:column}.dpm-input-row .dpm-button{width:100%}.dpm-plugin{flex-direction:column}.dpm-actions{width:100%;justify-content:flex-end}}
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

    function DesktopPluginManagerTab({ t }) {
      const bridge = window[BRIDGE_KEY]
      const [spec, setSpec] = React.useState('')
      const [confirmRemove, setConfirmRemove] = React.useState('')
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

      React.useEffect(() => {
        bridge?.request('status')
      }, [bridge])

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

      const operationText = state.busyOperation === 'install-plugin'
        ? t('installing')
        : state.busyOperation === 'remove-plugin'
          ? t('removing')
          : state.busyOperation === 'restart-harness'
            ? t('restarting')
            : ''

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

    function apply(ctx) {
      ctx.effect(() => ctx.locale.register(NS, { zh, en }), 'desktop plugin manager dictionaries')
      const t = ctx.locale.bind(NS)
      ctx.slots.inject('settings.plugins.tab', () => ctx.slots.register({
        name: 'settings.plugins.tab',
        id: 'desktop-manager',
        order: -10,
        label: () => t('tab'),
        locale: NS
      }, DesktopPluginManagerTab))
    }

    exports.NS = NS
    exports.apply = apply
    exports.inject = inject
    return module.exports
  }
})
