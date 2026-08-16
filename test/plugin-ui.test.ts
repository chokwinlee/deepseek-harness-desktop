import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { join } from 'node:path'
import test from 'node:test'

async function source(path: string) {
  return readFile(join(process.cwd(), path), 'utf8')
}

test('registers Desktop plugin management inside native Settings', async () => {
  const bridge = await source('src/recovery-bridge.js')
  const manager = await source('src/dsh-desktop-settings-plugin/lib/client.js')
  const patch = await source('src/dsh-desktop-settings-plugin/desktop.patch.yml')
  const native = await source('src-tauri/src/main.rs')

  assert.match(bridge, /dsh-desktop:\/\/action/)
  assert.match(bridge, /__DSH_ACTION_TOKEN__/)
  assert.match(bridge, /__DSH_DESKTOP_PLUGIN_MANAGER__/)
  assert.doesNotMatch(bridge, /plugins\.html|__DSH_PLUGIN_URL__/)
  assert.doesNotMatch(bridge, /__TAURI__|__TAURI_INTERNALS__|invoke\s*\(/)
  assert.doesNotMatch(bridge, /mountPluginEntry|aria-modal="true"/)
  assert.match(bridge, /dsh-desktop-plugin-rollback/)
  assert.match(bridge, /addEventListener\('load', startBridge/)
  assert.doesNotMatch(bridge, /handleInitialNotice\(\)\s*\n\s*request\('status'\)/)
  assert.match(bridge, /if \(payload\.pending\?\.state !== 'verifying'\) clearVerifyingNotice\(\)/)
  assert.match(bridge, /detail\.type === 'plugin-verified'[\s\S]*?clearVerifyingNotice\(\)/)
  assert.match(bridge, /removed: \{ title: `\$\{label\} 已移除`/)
  assert.match(bridge, /updated: \{ title: `\$\{label\} 已更新`/)
  assert.match(bridge, /disabled: \{ title: `\$\{label\} 已停用`/)
  assert.match(native, /"plugin-verified"[\s\S]*?"outcome": outcome/)

  assert.match(manager, /settings\.plugins\.tab/)
  assert.match(manager, /id: 'desktop-manager'/)
  assert.match(manager, /安装与管理/)
  assert.match(manager, /可直接粘贴 dsh plugin --profile web add 完整命令/)
  assert.match(manager, /remove-plugin/)
  assert.match(patch, /ui-settings-desktop-plugin-manager/)
  assert.match(native, /desktop_settings_patch_path/)
  assert.match(native, /command\.arg\("--patch"\)/)
})

test('asks for restart in place and links external CLI changes', async () => {
  const bridge = await source('src/recovery-bridge.js')
  const manager = await source('src/dsh-desktop-settings-plugin/lib/client.js')
  const native = await source('src-tauri/src/main.rs')
  assert.doesNotMatch(manager, /我已检查插件来源|第三方插件会在这台电脑上运行代码/)
  assert.match(manager, /在终端启用/)
  assert.match(manager, /重启 DSH/)
  assert.match(bridge, /立即重启/)
  assert.match(bridge, /稍后/)
  assert.match(bridge, /检测到命令行插件变更/)
  assert.match(native, /start_profile_watcher/)
  assert.match(native, /plugin-change-detected/)
  assert.match(native, /restart-required/)
})

test('keeps native title bar understated and synchronized with the Harness theme', async () => {
  const themeSync = await source('src/theme-sync.js')
  const native = await source('src-tauri/src/main.rs')

  assert.match(themeSync, /data-ds-dark-theme/)
  assert.match(themeSync, /--dsw-alias-bg-base/)
  assert.match(themeSync, /dsh-desktop:\/\/action\/\$\{SYNC_ACTION\}/)
  assert.match(themeSync, /MutationObserver\(scheduleSync\)/)
  assert.match(native, /\.title_bar_style\(tauri::TitleBarStyle::Overlay\)/)
  assert.match(native, /\.hidden_title\(true\)/)
  assert.match(native, /"sync-theme"/)
  assert.match(native, /window\.set_theme\(Some\(theme\)\)/)
  assert.match(native, /window\s*\.set_background_color/)
  assert.match(native, /let window = builder[\s\S]*?window\s*\.show\(\)[\s\S]*?window\s*\.set_focus\(\)/)
})

test('adds an app-wide usage meter backed by local session logs and live events', async () => {
  const meter = await source('src/usage-meter.js')
  const native = await source('src-tauri/src/main.rs')
  const manifest = await source('src-tauri/Cargo.toml')

  assert.match(meter, /usage-snapshot/)
  assert.match(meter, /\/api\/events\.mux/)
  assert.match(meter, /\/api\/events\.host/)
  assert.match(meter, /https:\/\/openrouter\.ai\/api\/v1\/models/)
  assert.match(meter, /deepseekOfficialPrice/)
  assert.match(meter, /projections\?\.values\?\.sessionStats/)
  assert.match(meter, /frame\.key === 'sessionStats'/)
  assert.doesNotMatch(meter, /TPS_WINDOW_MS|tokenSamples|estimateTokens/)
  assert.match(native, /session\.jsonl\.zstd/)
  assert.match(native, /usage_record_from_event/)
  assert.match(native, /USAGE_METER_SCRIPT/)
  assert.match(manifest, /zstd/)
})

test('ships smooth streaming as a default-on Desktop capability, not a DSH plugin', async () => {
  const smooth = await source('src/smooth-stream.js')
  const native = await source('src-tauri/src/main.rs')
  const electron = await source('src/main.ts')

  assert.match(smooth, /INITIAL_ENABLED = '__DSH_SMOOTH_STREAM_ENABLED__'/)
  assert.match(smooth, /settings\.general\.item/)
  assert.match(smooth, /data-chat-flow-kind="assistant-step"/)
  assert.match(smooth, /characterDataOldValue: true/)
  assert.match(smooth, /Intl\.Segmenter/)
  assert.match(smooth, /requestAnimationFrame\(revealTextFrame\)/)
  assert.match(smooth, /平滑流式输出/)
  assert.doesNotMatch(smooth, /__ModuleLoader__|conversation\.chat\.node|slots\.register/)
  assert.match(native, /SMOOTH_STREAM_SCRIPT/)
  assert.match(native, /\.initialization_script\(smooth_stream_script\)/)
  assert.match(native, /desktop-preferences\.json/)
  assert.match(electron, /injectSmoothStream/)
  assert.match(electron, /writeSmoothStreamPreference/)
})

test('ships a dedicated CLI launcher instead of the relocated npm bin file', async () => {
  const launcher = await source('src-tauri/src/bin/dsh.rs')
  const build = await source('scripts/build-tauri.sh')
  const tauri = JSON.parse(await source('src-tauri/tauri.conf.json'))
  assert.match(launcher, /@deepseek-ai\/dsh\/lib\/bin\.js/)
  assert.match(launcher, /--expose-internals/)
  assert.match(build, /binaries\/dsh-\$\{TRIPLE\}/)
  assert.match(build, /binaries\/pnpm-\$\{TRIPLE\}/)
  assert.deepEqual(tauri.bundle.externalBin, ['binaries/node', 'binaries/dsh', 'binaries/pnpm'])
  assert.doesNotMatch(build, /cp .*Contents\/MacOS\/(?:dsh|pnpm)/)
  assert.doesNotMatch(build, /codesign[\s\S]+Contents\/MacOS\/(?:dsh|pnpm)/)
  const bootstrap = build.indexOf('for CLI_SIDECAR_NAME in dsh pnpm')
  const compile = build.indexOf('cargo build --release --target "$TRIPLE" --bin dsh')
  const replace = build.indexOf('install -m 755 "$CLI_BINARY" "src-tauri/binaries/dsh-${TRIPLE}"')
  assert.ok(bootstrap >= 0 && bootstrap < compile)
  assert.ok(compile < replace)
})

test('runs desktop pnpm operations without an interactive terminal', async () => {
  const native = await source('src-tauri/src/main.rs')
  const helper = native.match(
    /fn apply_noninteractive_pnpm_environment[\s\S]*?\n}/,
  )?.[0]

  assert.ok(helper)
  assert.match(helper, /\.env\("CI", "true"\)/)
  assert.match(helper, /PNPM_CONFIG_CONFIRM_MODULES_PURGE/)
  assert.match(helper, /npm_config_confirm_modules_purge/)

  const calls = native.match(/apply_noninteractive_pnpm_environment\(&mut command\)/g)
  assert.equal(calls?.length, 2)
})

test('resynchronizes restored profile dependencies before recovery relaunch', async () => {
  const native = await source('src-tauri/src/main.rs')
  const restore = native.match(
    /if matches!\(action, RecoveryAction::Restore\)[\s\S]*?\n\s*}/,
  )?.[0]

  assert.ok(restore)
  assert.match(restore, /restore_last_known_good/)
  assert.match(restore, /sync_profile_modules_after_restore/)
  assert.match(restore, /set_recovery_state\("failed"/)
})
