#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::collections::{BTreeMap, BTreeSet, VecDeque};
use std::env;
use std::ffi::OsString;
use std::fs;
use std::io::{BufRead, BufReader};
#[cfg(unix)]
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{mpsc, Arc, LazyLock, Mutex};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use tauri::{Manager, Theme, WebviewUrl, WebviewWindowBuilder};
use tauri_plugin_opener::OpenerExt;
use uuid::Uuid;

const READINESS_MARK: &str = "dsh web:";
const STARTUP_TAIL_LINES: usize = 40;
const STARTUP_TIMEOUT: Duration = Duration::from_secs(120);
const READINESS_GRACE: Duration = Duration::from_millis(300);
const STOP_GRACE: Duration = Duration::from_secs(5);
const MONITOR_INTERVAL: Duration = Duration::from_millis(500);
const PROFILE_WATCH_INTERVAL: Duration = Duration::from_millis(750);
const PROFILE_STABLE_POLLS: u8 = 2;
const SNAPSHOT_STABILITY: Duration = Duration::from_secs(5);
const SAFE_PROFILE_NAME: &str = "desktop-safe";
const RECOVERY_DIR_NAME: &str = "desktop-recovery";
const BEFORE_PLUGIN_INSTALL: &str = "before-plugin-install";
const PENDING_CHANGE_FILE: &str = "pending-plugin-change.json";
const LEGACY_PENDING_INSTALL_FILE: &str = "pending-plugin-install.json";
const SNAPSHOT_FILES: [&str; 3] = ["package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml"];
const DESKTOP_PREFERENCES_FILE: &str = "desktop-preferences.json";
const PRODUCT_NAME: &str = "DSH Desktop";
const RECOVERY_TITLE: &str = "DSH Desktop — Recovery";

/// Update-checker client script, embedded at compile time and injected into
/// the harness webview. The `__DSH_CURRENT_VERSION__` placeholder is replaced with the shell's
/// own version below; see src/updater.js for what the script does.
const UPDATER_SCRIPT: &str = include_str!("../../src/updater.js");

/// Safe-mode banner injected into the Harness page. It is dormant during a
/// normal launch and exposes one route back to the user's ordinary profile.
const RECOVERY_BRIDGE_SCRIPT: &str = include_str!("../../src/recovery-bridge.js");

/// Mirrors Harness' resolved palette into the native title bar. This keeps
/// application-level light/dark choices independent from the macOS preference.
const THEME_SYNC_SCRIPT: &str = include_str!("../../src/theme-sync.js");

/// Native-log-backed usage summary and live title-bar throughput meter.
const USAGE_METER_SCRIPT: &str = include_str!("../../src/usage-meter.js");

/// Built-in, profile-independent streaming polish and its General Settings row.
const SMOOTH_STREAM_SCRIPT: &str = include_str!("../../src/smooth-stream.js");

/// Current shell version, kept in sync with package.json / tauri.conf.json.
const SHELL_VERSION: &str = env!("CARGO_PKG_VERSION");

static CHILD: Mutex<Option<Child>> = Mutex::new(None);
static CHILD_GENERATION: AtomicU64 = AtomicU64::new(0);
static OPERATION_ACTIVE: AtomicBool = AtomicBool::new(false);
static PROFILE_WATCHER_STARTED: AtomicBool = AtomicBool::new(false);
static ALLOWED_HARNESS_ORIGIN: LazyLock<Mutex<Option<String>>> = LazyLock::new(|| Mutex::new(None));
static CURRENT_HARNESS_URL: LazyLock<Mutex<Option<String>>> = LazyLock::new(|| Mutex::new(None));
static LOADED_PLUGIN_STATE: LazyLock<Mutex<Option<serde_json::Value>>> =
    LazyLock::new(|| Mutex::new(None));
static DESKTOP_ACTION_TOKEN: LazyLock<String> = LazyLock::new(|| {
    env::var("DSH_DESKTOP_ACTION_TOKEN")
        .ok()
        .filter(|token| token.len() >= 16 && token.chars().all(|ch| ch.is_ascii_alphanumeric()))
        .unwrap_or_else(|| Uuid::new_v4().simple().to_string())
});
static RECOVERY_STATE: LazyLock<Mutex<RecoveryState>> =
    LazyLock::new(|| Mutex::new(RecoveryState::default()));

type StartupTail = Arc<Mutex<VecDeque<String>>>;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum LaunchMode {
    Normal,
    Safe,
}

#[derive(Clone, Debug)]
enum HarnessNotice {
    InstallVerifying(String),
    InstallRolledBack(String),
}

impl LaunchMode {
    fn profile_name(self) -> &'static str {
        match self {
            Self::Normal => "web",
            Self::Safe => SAFE_PROFILE_NAME,
        }
    }
}

#[derive(Debug)]
struct RecoveryState {
    phase: String,
    error: String,
    safe_mode: bool,
}

impl Default for RecoveryState {
    fn default() -> Self {
        Self {
            phase: "starting".into(),
            error: String::new(),
            safe_mode: false,
        }
    }
}

struct OperationGuard;

impl OperationGuard {
    fn acquire() -> Result<Self, String> {
        OPERATION_ACTIVE
            .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
            .map(|_| Self)
            .map_err(|_| "另一项恢复操作正在进行，请稍候。".into())
    }
}

impl Drop for OperationGuard {
    fn drop(&mut self) {
        OPERATION_ACTIVE.store(false, Ordering::SeqCst);
    }
}

#[derive(Debug)]
struct HarnessPaths {
    home: PathBuf,
    dsh_home: PathBuf,
}

fn redact_startup_line(line: &str) -> String {
    let lower = line.to_ascii_lowercase();
    let sensitive = [
        "api_key",
        "api-key",
        "apikey",
        "authorization",
        "bearer ",
        "password",
        "token=",
        "token:",
    ]
    .iter()
    .any(|marker| lower.contains(marker));
    if sensitive {
        return "[redacted sensitive startup detail]".into();
    }
    line.chars().take(2_000).collect()
}

fn record_startup_line(tail: &StartupTail, source: &str, line: &str) -> String {
    let safe = redact_startup_line(line);
    if !safe.is_empty() {
        if let Ok(mut lines) = tail.lock() {
            lines.push_back(format!("{source}: {safe}"));
            while lines.len() > STARTUP_TAIL_LINES {
                lines.pop_front();
            }
        }
    }
    safe
}

fn startup_tail_text(tail: &StartupTail) -> String {
    let Ok(lines) = tail.lock() else {
        return String::new();
    };
    if lines.is_empty() {
        String::new()
    } else {
        format!(
            "\n\nRecent Harness output:\n{}",
            lines.iter().cloned().collect::<Vec<_>>().join("\n")
        )
    }
}

fn set_recovery_state(phase: &str, error: impl Into<String>, safe_mode: bool) {
    if let Ok(mut state) = RECOVERY_STATE.lock() {
        state.phase = phase.into();
        state.error = error.into();
        state.safe_mode = safe_mode;
    }
}

fn valid_package_name(value: &str) -> bool {
    if value.is_empty() || value.len() > 214 || value.contains(char::is_whitespace) {
        return false;
    }
    let valid_segment = |segment: &str| {
        !segment.is_empty()
            && segment
                .chars()
                .all(|ch| ch.is_ascii_alphanumeric() || matches!(ch, '.' | '_' | '~' | '-'))
    };
    if let Some(scoped) = value.strip_prefix('@') {
        let Some((scope, package)) = scoped.split_once('/') else {
            return false;
        };
        valid_segment(scope) && valid_segment(package) && !package.contains('/')
    } else {
        valid_segment(value) && !value.contains('/')
    }
}

fn detected_plugin(error: &str) -> Option<String> {
    const MARKER: &str = "failed to apply loader entry";
    error.lines().rev().find_map(|line| {
        let marker = line.find(MARKER)?;
        let suffix = &line[marker + MARKER.len()..];
        let open = suffix.rfind('(')?;
        let close = suffix[open + 1..].find(')')? + open + 1;
        let package = suffix[open + 1..close].trim();
        valid_package_name(package).then(|| package.to_string())
    })
}

fn harness_paths() -> HarnessPaths {
    let spike_home = env::var("SPIKE_HOME").ok();
    let home = spike_home
        .as_ref()
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env::var("HOME").unwrap_or_default()));
    let dsh_home = spike_home
        .map(|value| PathBuf::from(value).join(".dsh"))
        .unwrap_or_else(|| {
            env::var("DSH_HOME")
                .map(PathBuf::from)
                .unwrap_or_else(|_| home.join(".dsh"))
        });
    HarnessPaths { home, dsh_home }
}

fn recovery_root(dsh_home: &Path) -> PathBuf {
    dsh_home.join(RECOVERY_DIR_NAME)
}

fn snapshot_dir(dsh_home: &Path) -> PathBuf {
    snapshot_dir_named(dsh_home, "last-known-good")
}

fn snapshot_dir_named(dsh_home: &Path, name: &str) -> PathBuf {
    recovery_root(dsh_home).join(name)
}

fn snapshot_available_at(dsh_home: &Path) -> bool {
    snapshot_dir(dsh_home).join("package.json").is_file()
}

fn atomic_write(path: &Path, contents: &[u8]) -> Result<(), String> {
    let parent = path
        .parent()
        .ok_or_else(|| format!("invalid recovery path {}", path.display()))?;
    fs::create_dir_all(parent)
        .map_err(|error| format!("failed to create {}: {error}", parent.display()))?;
    let temporary = parent.join(format!(
        ".{}.desktop-recovery-{}",
        path.file_name()
            .and_then(|name| name.to_str())
            .unwrap_or("file"),
        std::process::id()
    ));
    fs::write(&temporary, contents)
        .map_err(|error| format!("failed to write {}: {error}", temporary.display()))?;
    #[cfg(windows)]
    if path.exists() {
        fs::remove_file(path)
            .map_err(|error| format!("failed to replace {}: {error}", path.display()))?;
    }
    fs::rename(&temporary, path)
        .map_err(|error| format!("failed to commit {}: {error}", path.display()))
}

fn desktop_preferences_path(dsh_home: &Path) -> PathBuf {
    dsh_home.join(DESKTOP_PREFERENCES_FILE)
}

fn read_desktop_preferences(path: &Path) -> Result<serde_json::Value, String> {
    let contents = match fs::read_to_string(path) {
        Ok(contents) => contents,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            return Ok(serde_json::json!({}));
        }
        Err(error) => return Err(format!("failed to read {}: {error}", path.display())),
    };
    let preferences: serde_json::Value = serde_json::from_str(&contents)
        .map_err(|error| format!("invalid Desktop preferences at {}: {error}", path.display()))?;
    if !preferences.is_object() {
        return Err(format!(
            "Desktop preferences at {} must be an object",
            path.display()
        ));
    }
    Ok(preferences)
}

fn smooth_stream_enabled_from(preferences: &serde_json::Value) -> bool {
    preferences
        .get("smoothStreamEnabled")
        .and_then(serde_json::Value::as_bool)
        .unwrap_or(true)
}

fn smooth_stream_enabled_at(path: &Path) -> bool {
    read_desktop_preferences(path)
        .map(|preferences| smooth_stream_enabled_from(&preferences))
        .unwrap_or_else(|error| {
            eprintln!("[dsh] smooth stream preference warning: {error}");
            true
        })
}

fn write_smooth_stream_preference(path: &Path, enabled: bool) -> Result<(), String> {
    let mut preferences = read_desktop_preferences(path)?;
    preferences["smoothStreamEnabled"] = serde_json::Value::Bool(enabled);
    let encoded = serde_json::to_vec_pretty(&preferences)
        .map_err(|error| format!("failed to encode Desktop preferences: {error}"))?;
    let mut contents = encoded;
    contents.push(b'\n');
    atomic_write(path, &contents)
}

fn copy_atomic(source: &Path, destination: &Path) -> Result<(), String> {
    let contents = fs::read(source)
        .map_err(|error| format!("failed to read {}: {error}", source.display()))?;
    atomic_write(destination, &contents)
}

fn write_profile_snapshot(dsh_home: &Path, name: &str) -> Result<(), String> {
    let source = dsh_home.join("profiles/web");
    let root = recovery_root(dsh_home);
    let next = root.join(format!(".{name}-next-{}", std::process::id()));
    let target = root.join(name);
    let previous = root.join(format!(".{name}-previous"));
    if next.exists() {
        fs::remove_dir_all(&next)
            .map_err(|error| format!("failed to clear {}: {error}", next.display()))?;
    }
    fs::create_dir_all(&next)
        .map_err(|error| format!("failed to create {}: {error}", next.display()))?;

    let mut present = Vec::new();
    for filename in SNAPSHOT_FILES {
        let source_file = source.join(filename);
        if source_file.is_file() {
            fs::copy(&source_file, next.join(filename)).map_err(|error| {
                format!("failed to snapshot {}: {error}", source_file.display())
            })?;
            present.push(filename);
        }
    }
    if !present.contains(&"package.json") {
        return Err(format!(
            "profile manifest is missing at {}",
            source.display()
        ));
    }
    let created_at = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis();
    let metadata = serde_json::to_vec_pretty(&serde_json::json!({
        "version": 1,
        "createdAtUnixMs": created_at,
        "files": present,
    }))
    .map_err(|error| format!("failed to encode recovery snapshot: {error}"))?;
    fs::write(next.join("snapshot.json"), metadata)
        .map_err(|error| format!("failed to write recovery snapshot metadata: {error}"))?;

    if previous.exists() {
        fs::remove_dir_all(&previous)
            .map_err(|error| format!("failed to clear {}: {error}", previous.display()))?;
    }
    if target.exists() {
        fs::rename(&target, &previous)
            .map_err(|error| format!("failed to rotate {}: {error}", target.display()))?;
    }
    if let Err(error) = fs::rename(&next, &target) {
        if previous.exists() && !target.exists() {
            let _ = fs::rename(&previous, &target);
        }
        return Err(format!("failed to commit {}: {error}", target.display()));
    }
    if previous.exists() {
        let _ = fs::remove_dir_all(previous);
    }
    Ok(())
}

fn restore_profile_snapshot(
    dsh_home: &Path,
    snapshot_name: &str,
    backup_name: Option<&str>,
) -> Result<(), String> {
    let source = snapshot_dir_named(dsh_home, snapshot_name);
    let metadata_path = source.join("snapshot.json");
    let metadata: serde_json::Value = serde_json::from_slice(
        &fs::read(&metadata_path)
            .map_err(|error| format!("failed to read {}: {error}", metadata_path.display()))?,
    )
    .map_err(|error| format!("invalid recovery snapshot metadata: {error}"))?;
    let present: BTreeSet<&str> = metadata["files"]
        .as_array()
        .ok_or("recovery snapshot does not list its files")?
        .iter()
        .filter_map(serde_json::Value::as_str)
        .collect();
    if !present.contains("package.json") {
        return Err("recovery snapshot does not contain package.json".into());
    }

    if let Some(name) = backup_name {
        write_profile_snapshot(dsh_home, name)?;
    }
    let destination = dsh_home.join("profiles/web");
    fs::create_dir_all(&destination)
        .map_err(|error| format!("failed to create {}: {error}", destination.display()))?;
    for filename in SNAPSHOT_FILES {
        let destination_file = destination.join(filename);
        if present.contains(filename) {
            copy_atomic(&source.join(filename), &destination_file)?;
        } else if destination_file.exists() {
            fs::remove_file(&destination_file).map_err(|error| {
                format!(
                    "failed to restore absence of {}: {error}",
                    destination_file.display()
                )
            })?;
        }
    }
    Ok(())
}

fn restore_last_known_good(dsh_home: &Path) -> Result<(), String> {
    restore_profile_snapshot(dsh_home, "last-known-good", Some("before-restore"))
}

fn pending_install_path(dsh_home: &Path) -> PathBuf {
    recovery_root(dsh_home).join(PENDING_CHANGE_FILE)
}

fn legacy_pending_install_path(dsh_home: &Path) -> PathBuf {
    recovery_root(dsh_home).join(LEGACY_PENDING_INSTALL_FILE)
}

fn read_pending_install(dsh_home: &Path) -> Result<Option<serde_json::Value>, String> {
    let current = pending_install_path(dsh_home);
    let legacy = legacy_pending_install_path(dsh_home);
    let path = if current.is_file() {
        current
    } else if legacy.is_file() {
        legacy
    } else {
        return Ok(None);
    };
    if !path.is_file() {
        return Ok(None);
    }
    let value: serde_json::Value = serde_json::from_slice(
        &fs::read(&path).map_err(|error| format!("failed to read {}: {error}", path.display()))?,
    )
    .map_err(|error| format!("invalid pending plugin transaction: {error}"))?;
    let version = value["version"].as_u64();
    let valid_v1 = version == Some(1) && value["spec"].as_str().is_some();
    let valid_v2 = version == Some(2)
        && value["state"].as_str().is_some()
        && value["source"].as_str().is_some();
    if !valid_v1 && !valid_v2 {
        return Err("invalid pending plugin transaction metadata".into());
    }
    Ok(Some(value))
}

struct PendingChange<'a> {
    source: &'a str,
    spec: Option<&'a str>,
    state: &'a str,
    packages: &'a [String],
    changes: &'a [serde_json::Value],
    rollback_snapshot: &'a str,
    before_fingerprint: Option<&'a str>,
    after_fingerprint: Option<&'a str>,
}

fn write_pending_change(dsh_home: &Path, change: PendingChange<'_>) -> Result<(), String> {
    let started_at = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis();
    let contents = serde_json::to_vec_pretty(&serde_json::json!({
        "version": 2,
        "source": change.source,
        "spec": change.spec,
        "state": change.state,
        "packages": change.packages,
        "changes": change.changes,
        "rollbackSnapshot": change.rollback_snapshot,
        "beforeFingerprint": change.before_fingerprint,
        "afterFingerprint": change.after_fingerprint,
        "updatedAtUnixMs": started_at,
    }))
    .map_err(|error| format!("failed to encode plugin transaction: {error}"))?;
    atomic_write(&pending_install_path(dsh_home), &contents)
}

fn rewrite_pending_state(
    dsh_home: &Path,
    pending: &serde_json::Value,
    state: &str,
) -> Result<(), String> {
    if pending["version"].as_u64() == Some(1) {
        let packages = pending_packages(pending);
        return write_pending_change(
            dsh_home,
            PendingChange {
                source: "desktop",
                spec: pending["spec"].as_str(),
                state,
                packages: &packages,
                changes: &[],
                rollback_snapshot: BEFORE_PLUGIN_INSTALL,
                before_fingerprint: None,
                after_fingerprint: None,
            },
        );
    }
    write_pending_change(
        dsh_home,
        PendingChange {
            source: pending["source"].as_str().unwrap_or("desktop"),
            spec: pending["spec"].as_str(),
            state,
            packages: &pending_packages(pending),
            changes: pending["changes"]
                .as_array()
                .map(Vec::as_slice)
                .unwrap_or(&[]),
            rollback_snapshot: pending["rollbackSnapshot"]
                .as_str()
                .unwrap_or(BEFORE_PLUGIN_INSTALL),
            before_fingerprint: pending["beforeFingerprint"].as_str(),
            after_fingerprint: pending["afterFingerprint"].as_str(),
        },
    )
}

fn clear_pending_install(dsh_home: &Path) -> Result<(), String> {
    for marker in [
        pending_install_path(dsh_home),
        legacy_pending_install_path(dsh_home),
    ] {
        if marker.exists() {
            fs::remove_file(&marker)
                .map_err(|error| format!("failed to clear {}: {error}", marker.display()))?;
        }
    }
    let snapshot = snapshot_dir_named(dsh_home, BEFORE_PLUGIN_INSTALL);
    if snapshot.exists() {
        fs::remove_dir_all(&snapshot)
            .map_err(|error| format!("failed to clear {}: {error}", snapshot.display()))?;
    }
    Ok(())
}

fn pending_install_label(value: &serde_json::Value) -> String {
    value["changes"]
        .as_array()
        .and_then(|items| items.first())
        .and_then(|change| change["name"].as_str())
        .or_else(|| {
            value["packages"]
                .as_array()
                .and_then(|items| items.first())
                .and_then(serde_json::Value::as_str)
        })
        .or_else(|| value["spec"].as_str())
        .unwrap_or("插件配置")
        .chars()
        .take(120)
        .collect()
}

fn validate_plugin_spec(raw: &str) -> Result<String, String> {
    let input = raw.trim();
    if input.is_empty() {
        return Err("请输入 npm 包名或 GitHub 仓库地址。".into());
    }

    let parts: Vec<&str> = input.split_ascii_whitespace().collect();
    let spec = match parts.as_slice() {
        [spec] => *spec,
        ["dsh" | "dsh.exe", "plugin", "--profile", "web", "add", spec]
        | ["dsh" | "dsh.exe", "plugin", "--profile=web", "add", spec] => *spec,
        _ => {
            return Err(
                "请输入插件地址，或粘贴完整命令：dsh plugin --profile web add <插件地址>。".into(),
            )
        }
    };
    if spec.len() > 512 || spec.chars().any(char::is_whitespace) {
        return Err("插件地址不能包含空格，且长度不能超过 512 个字符。".into());
    }
    if spec.starts_with('-')
        || spec.starts_with('.')
        || spec.starts_with('/')
        || spec.starts_with('~')
        || ["file:", "link:", "workspace:", "ssh:", "git+ssh:"]
            .iter()
            .any(|prefix| spec.starts_with(prefix))
    {
        return Err(
            "桌面安装器只接受 npm 包或公开 GitHub HTTPS 地址，不接受参数、本地路径或 SSH 地址。"
                .into(),
        );
    }
    if (spec.starts_with("http:") || spec.starts_with("https:") || spec.starts_with("git+https:"))
        && !(spec.starts_with("https://github.com/") || spec.starts_with("git+https://github.com/"))
    {
        return Err("桌面安装器目前只接受 github.com 上的 HTTPS 仓库地址。".into());
    }
    let allowed = |ch: char| {
        ch.is_ascii_alphanumeric()
            || matches!(
                ch,
                '@' | '/' | '.' | '_' | '~' | ':' | '+' | '#' | '=' | '-'
            )
    };
    if !spec.chars().all(allowed) {
        return Err("插件地址包含桌面安装器不支持的字符。".into());
    }
    Ok(spec.into())
}

fn read_web_manifest(dsh_home: &Path) -> Result<serde_json::Value, String> {
    let path = dsh_home.join("profiles/web/package.json");
    serde_json::from_slice(
        &fs::read(&path).map_err(|error| format!("failed to read {}: {error}", path.display()))?,
    )
    .map_err(|error| format!("invalid web profile manifest: {error}"))
}

fn installed_plugins(manifest: &serde_json::Value) -> Vec<serde_json::Value> {
    let active: BTreeSet<&str> = manifest["dsh"]["profile"]["bundles"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(serde_json::Value::as_str)
        .collect();
    let mut plugins: Vec<_> = manifest["dependencies"]
        .as_object()
        .into_iter()
        .flatten()
        .map(|(name, spec)| {
            serde_json::json!({
                "name": name,
                "spec": spec.as_str().unwrap_or(""),
                "active": active.contains(name.as_str()),
            })
        })
        .collect();
    plugins.sort_by(|left, right| left["name"].as_str().cmp(&right["name"].as_str()));
    plugins
}

fn plugin_profile_state(manifest: &serde_json::Value) -> serde_json::Value {
    serde_json::json!({ "plugins": installed_plugins(manifest) })
}

fn plugin_state_fingerprint(state: &serde_json::Value) -> String {
    let encoded = serde_json::to_vec(state).unwrap_or_default();
    let mut hash = 0xcbf29ce484222325_u64;
    for byte in encoded {
        hash ^= u64::from(byte);
        hash = hash.wrapping_mul(0x100000001b3);
    }
    format!("{hash:016x}")
}

fn read_plugin_state(dsh_home: &Path) -> Result<serde_json::Value, String> {
    read_web_manifest(dsh_home).map(|manifest| plugin_profile_state(&manifest))
}

fn snapshot_plugin_state(dsh_home: &Path, name: &str) -> Result<serde_json::Value, String> {
    let path = snapshot_dir_named(dsh_home, name).join("package.json");
    let manifest: serde_json::Value = serde_json::from_slice(
        &fs::read(&path).map_err(|error| format!("failed to read {}: {error}", path.display()))?,
    )
    .map_err(|error| format!("invalid snapshot manifest: {error}"))?;
    Ok(plugin_profile_state(&manifest))
}

fn plugin_state_map(state: &serde_json::Value) -> BTreeMap<String, (String, bool)> {
    state["plugins"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|plugin| {
            Some((
                plugin["name"].as_str()?.to_string(),
                (
                    plugin["spec"].as_str().unwrap_or_default().to_string(),
                    plugin["active"].as_bool().unwrap_or(false),
                ),
            ))
        })
        .collect()
}

fn plugin_state_changes(
    before: &serde_json::Value,
    after: &serde_json::Value,
) -> Vec<serde_json::Value> {
    let before = plugin_state_map(before);
    let after = plugin_state_map(after);
    let names: BTreeSet<&str> = before
        .keys()
        .chain(after.keys())
        .map(String::as_str)
        .collect();
    names
        .into_iter()
        .filter_map(|name| match (before.get(name), after.get(name)) {
            (None, Some((spec, active))) => Some(serde_json::json!({
                "name": name, "kind": "installed", "spec": spec, "active": active
            })),
            (Some((spec, active)), None) => Some(serde_json::json!({
                "name": name, "kind": "removed", "spec": spec, "active": active
            })),
            (Some((before_spec, before_active)), Some((after_spec, after_active)))
                if before_spec != after_spec =>
            {
                Some(serde_json::json!({
                    "name": name,
                    "kind": "updated",
                    "beforeSpec": before_spec,
                    "spec": after_spec,
                    "active": after_active,
                }))
            }
            (Some((_, before_active)), Some((spec, after_active)))
                if before_active != after_active =>
            {
                Some(serde_json::json!({
                    "name": name,
                    "kind": if *after_active { "activated" } else { "deactivated" },
                    "spec": spec,
                    "active": after_active,
                }))
            }
            _ => None,
        })
        .collect()
}

fn changed_plugin_names(changes: &[serde_json::Value]) -> Vec<String> {
    changes
        .iter()
        .filter_map(|change| change["name"].as_str())
        .map(str::to_string)
        .collect()
}

fn pending_change_outcome(pending: &serde_json::Value) -> &'static str {
    let kinds: BTreeSet<&str> = pending["changes"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|change| change["kind"].as_str())
        .collect();
    if kinds.len() != 1 {
        return "changed";
    }
    match kinds.first().copied() {
        Some("removed") => "removed",
        Some("updated") => "updated",
        Some("deactivated") => "disabled",
        Some("installed" | "activated") => "enabled",
        _ => "changed",
    }
}

fn profile_dependencies_ready(dsh_home: &Path, state: &serde_json::Value) -> bool {
    let modules = dsh_home.join("profiles/web/node_modules");
    state["plugins"]
        .as_array()
        .into_iter()
        .flatten()
        .all(|plugin| {
            plugin["name"]
                .as_str()
                .map(|name| modules.join(name).join("package.json").is_file())
                .unwrap_or(false)
        })
}

fn record_external_change(
    dsh_home: &Path,
    before: &serde_json::Value,
    after: &serde_json::Value,
    state: &str,
) -> Result<Option<serde_json::Value>, String> {
    let changes = plugin_state_changes(before, after);
    if changes.is_empty() {
        return Ok(None);
    }
    let packages = changed_plugin_names(&changes);
    let before_fingerprint = plugin_state_fingerprint(before);
    let after_fingerprint = plugin_state_fingerprint(after);
    write_pending_change(
        dsh_home,
        PendingChange {
            source: "cli",
            spec: None,
            state,
            packages: &packages,
            changes: &changes,
            rollback_snapshot: "last-known-good",
            before_fingerprint: Some(&before_fingerprint),
            after_fingerprint: Some(&after_fingerprint),
        },
    )?;
    read_pending_install(dsh_home)
}

fn detect_external_change_before_launch(dsh_home: &Path) -> Result<(), String> {
    if read_pending_install(dsh_home)?.is_some() || !snapshot_available_at(dsh_home) {
        return Ok(());
    }
    let before = snapshot_plugin_state(dsh_home, "last-known-good")?;
    let after = read_plugin_state(dsh_home)?;
    if plugin_state_fingerprint(&before) != plugin_state_fingerprint(&after) {
        let _ = record_external_change(dsh_home, &before, &after, "restart-required")?;
        println!("[dsh] detected plugin profile changes made while desktop was not running");
    }
    Ok(())
}

fn safe_profile_manifest(source: &serde_json::Value) -> Result<serde_json::Value, String> {
    let mut manifest = source.clone();
    let dependencies: BTreeSet<&str> = source["dependencies"]
        .as_object()
        .map(|items| items.keys().map(String::as_str).collect())
        .unwrap_or_default();
    let bundles = source["dsh"]["profile"]["bundles"]
        .as_array()
        .ok_or("web profile does not contain dsh.profile.bundles")?;
    let safe_bundles: Vec<serde_json::Value> = bundles
        .iter()
        .filter(|bundle| {
            bundle
                .as_str()
                .map(|name| !dependencies.contains(name))
                .unwrap_or(false)
        })
        .cloned()
        .collect();
    if safe_bundles.is_empty() {
        return Err("could not identify any built-in web profile bundles".into());
    }
    manifest["name"] = serde_json::Value::String("dsh-profile-desktop-safe".into());
    manifest["private"] = serde_json::Value::Bool(true);
    manifest["dsh"]["profile"]["bundles"] = serde_json::Value::Array(safe_bundles);
    Ok(manifest)
}

fn prepare_safe_profile(dsh_home: &Path) -> Result<(), String> {
    let web_manifest = dsh_home.join("profiles/web/package.json");
    let source: serde_json::Value = serde_json::from_slice(
        &fs::read(&web_manifest)
            .map_err(|error| format!("failed to read {}: {error}", web_manifest.display()))?,
    )
    .map_err(|error| format!("invalid web profile manifest: {error}"))?;
    let safe = safe_profile_manifest(&source)?;
    let safe_dir = dsh_home.join("profiles").join(SAFE_PROFILE_NAME);
    let contents = serde_json::to_vec_pretty(&safe)
        .map_err(|error| format!("failed to encode safe profile: {error}"))?;
    let mut contents_with_newline = contents;
    contents_with_newline.push(b'\n');
    atomic_write(&safe_dir.join("package.json"), &contents_with_newline)?;
    atomic_write(&safe_dir.join("cordis.patch.yml"), b"[]\n")?;
    Ok(())
}

fn target_triple() -> &'static str {
    match (std::env::consts::ARCH, std::env::consts::OS) {
        ("aarch64", "macos") => "aarch64-apple-darwin",
        ("x86_64", "macos") => "x86_64-apple-darwin",
        ("x86_64", "windows") => "x86_64-pc-windows-msvc",
        ("aarch64", "windows") => "aarch64-pc-windows-msvc",
        ("x86_64", "linux") => "x86_64-unknown-linux-gnu",
        ("aarch64", "linux") => "aarch64-unknown-linux-gnu",
        (arch, os) => panic!("unsupported target: {arch}-{os}"),
    }
}

fn exe_dir() -> PathBuf {
    env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(|d| d.to_path_buf()))
        .unwrap_or_else(|| PathBuf::from("."))
}

/// Candidate roots that may contain the bundled node_modules, most specific first.
fn resource_roots() -> Vec<PathBuf> {
    let exe = exe_dir();
    let mut roots = Vec::new();
    if let Some(contents) = exe.parent() {
        roots.push(contents.join("Resources"));
        roots.push(contents.join("Resources/_up_"));
    }
    roots.push(exe.join("../../.."));
    #[cfg(debug_assertions)]
    roots.push(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join(".."));
    if let Ok(cwd) = env::current_dir() {
        roots.push(cwd);
    }
    roots
}

/// Bundled Node sidecar (externalBin) next to the executable; DSH_NODE overrides.
fn resolve_node() -> PathBuf {
    if let Ok(path) = env::var("DSH_NODE") {
        return PathBuf::from(path);
    }
    let exe = exe_dir();
    let triple = target_triple();
    for name in [format!("node-{triple}"), "node".to_string()] {
        let candidate = exe.join(name);
        if candidate.exists() {
            return candidate;
        }
    }
    PathBuf::from("node")
}

/// dsh CLI entry in bundled resources; DSH_SCRIPT overrides.
fn resolve_script() -> PathBuf {
    if let Ok(path) = env::var("DSH_SCRIPT") {
        return PathBuf::from(path);
    }
    resolve_modules_directory().join("@deepseek-ai/dsh/lib/bin.js")
}

fn resolve_modules_directory() -> PathBuf {
    for root in resource_roots() {
        let candidate = root.join("node_modules");
        if candidate.join("@deepseek-ai/dsh/lib/bin.js").exists() {
            return candidate;
        }
    }
    PathBuf::from("node_modules")
}

fn resolve_onboarding_helper() -> PathBuf {
    for root in resource_roots() {
        for relative in [
            "scripts/acknowledge-onboarding.mjs",
            "src-tauri/scripts/acknowledge-onboarding.mjs",
        ] {
            let candidate = root.join(relative);
            if candidate.exists() {
                return candidate;
            }
        }
    }
    PathBuf::from("scripts/acknowledge-onboarding.mjs")
}

fn desktop_settings_patch_path() -> PathBuf {
    resolve_modules_directory()
        .join("dsh-desktop-settings-plugin")
        .join("desktop.patch.yml")
}

fn ensure_desktop_settings_module_link(dsh_home: &Path) -> Result<(), String> {
    let source = resolve_modules_directory().join("dsh-desktop-settings-plugin");
    if !source.join("package.json").is_file() {
        return Err(format!(
            "桌面安装包缺少 Settings 插件模块：{}",
            source.display()
        ));
    }
    let modules = dsh_home.join("profiles/node_modules");
    fs::create_dir_all(&modules)
        .map_err(|error| format!("无法创建 {}：{error}", modules.display()))?;
    let link = modules.join("dsh-desktop-settings-plugin");
    if let Ok(metadata) = fs::symlink_metadata(&link) {
        if !metadata.file_type().is_symlink() {
            return Err(format!(
                "{} 已存在且不属于桌面版，无法加载 Settings 插件。",
                link.display()
            ));
        }
        if same_file(&link, &source) {
            return Ok(());
        }
        fs::remove_file(&link).map_err(|error| format!("无法更新 {}：{error}", link.display()))?;
    }
    #[cfg(unix)]
    std::os::unix::fs::symlink(&source, &link)
        .map_err(|error| format!("无法链接 {}：{error}", link.display()))?;
    #[cfg(windows)]
    std::os::windows::fs::symlink_dir(&source, &link)
        .map_err(|error| format!("无法链接 {}：{error}", link.display()))?;
    Ok(())
}

fn bundled_pnpm_path() -> PathBuf {
    let name = if cfg!(windows) { "pnpm.cmd" } else { "pnpm" };
    let launcher = exe_dir().join(name);
    if launcher.is_file() {
        return launcher;
    }
    resolve_modules_directory().join(".bin").join(name)
}

fn bundled_pnpm_script() -> PathBuf {
    resolve_modules_directory()
        .join("pnpm")
        .join("bin")
        .join("pnpm.mjs")
}

fn bundled_cli_path() -> PathBuf {
    let name = if cfg!(windows) { "dsh.exe" } else { "dsh" };
    let candidate = exe_dir().join(name);
    if candidate.is_file() {
        return candidate;
    }
    exe_dir().join(format!("dsh-{}", target_triple()))
}

fn managed_cli_path() -> PathBuf {
    harness_paths().home.join(".local/bin/dsh")
}

fn command_on_path(name: &str) -> Option<PathBuf> {
    env::var_os("PATH").and_then(|path| {
        env::split_paths(&path).find_map(|directory| {
            let candidate = directory.join(name);
            candidate.is_file().then_some(candidate)
        })
    })
}

fn same_file(left: &Path, right: &Path) -> bool {
    match (fs::canonicalize(left), fs::canonicalize(right)) {
        (Ok(left), Ok(right)) => left == right,
        _ => false,
    }
}

fn shell_profile_path() -> Option<PathBuf> {
    let home = harness_paths().home;
    let shell = env::var("SHELL").unwrap_or_default();
    if shell.ends_with("/bash") {
        Some(home.join(".bash_profile"))
    } else if shell.is_empty() || shell.ends_with("/zsh") {
        Some(home.join(".zprofile"))
    } else {
        None
    }
}

const CLI_PATH_MARKER: &str = "# DSH Desktop CLI";
const LEGACY_CLI_PATH_MARKER: &str = "# DeepSeek Harness Desktop CLI";
const CLI_PATH_BLOCK: &str = "# DSH Desktop CLI\nexport PATH=\"$HOME/.local/bin:$PATH\"\n";
const LEGACY_CLI_PATH_BLOCK: &str =
    "# DeepSeek Harness Desktop CLI\nexport PATH=\"$HOME/.local/bin:$PATH\"\n";

fn shell_profile_has_cli_path() -> bool {
    shell_profile_path()
        .and_then(|path| fs::read_to_string(path).ok())
        .map(|contents| {
            contents.contains(CLI_PATH_MARKER) || contents.contains(LEGACY_CLI_PATH_MARKER)
        })
        .unwrap_or(false)
}

fn without_cli_path_block(contents: &str) -> String {
    [CLI_PATH_BLOCK, LEGACY_CLI_PATH_BLOCK].into_iter().fold(
        contents.to_string(),
        |current, block| {
            current
                .replace(&format!("\n{block}"), "\n")
                .replace(block, "")
        },
    )
}

fn ensure_shell_cli_path(force_prepend: bool) -> Result<bool, String> {
    let command = if cfg!(windows) { "dsh.exe" } else { "dsh" };
    let bundled = bundled_cli_path();
    let command_uses_bundled = command_on_path(command)
        .map(|path| same_file(&path, &bundled))
        .unwrap_or(false);
    if !force_prepend && (command_uses_bundled || shell_profile_has_cli_path()) {
        return Ok(false);
    }
    let Some(profile) = shell_profile_path() else {
        return Ok(false);
    };
    let contents = fs::read_to_string(&profile).unwrap_or_default();
    let contents = without_cli_path_block(&contents);
    let contents = contents.trim_end_matches('\n');
    let updated = if contents.is_empty() {
        CLI_PATH_BLOCK.to_string()
    } else {
        format!("{contents}\n\n{CLI_PATH_BLOCK}")
    };
    atomic_write(&profile, updated.as_bytes())?;
    Ok(true)
}

fn remove_shell_cli_path() -> Result<(), String> {
    let Some(profile) = shell_profile_path() else {
        return Ok(());
    };
    let Ok(contents) = fs::read_to_string(&profile) else {
        return Ok(());
    };
    let updated = without_cli_path_block(&contents);
    if updated != contents {
        atomic_write(&profile, updated.as_bytes())?;
    }
    Ok(())
}

fn bundled_dsh_version() -> Option<String> {
    let manifest = resolve_modules_directory().join("@deepseek-ai/dsh/package.json");
    fs::read(&manifest)
        .ok()
        .and_then(|contents| serde_json::from_slice::<serde_json::Value>(&contents).ok())
        .and_then(|value| value["version"].as_str().map(str::to_string))
}

fn cli_status_value() -> serde_json::Value {
    let bundled = bundled_cli_path();
    let managed = managed_cli_path();
    let launcher_installed = managed.is_file() && same_file(&managed, &bundled);
    let existing = command_on_path(if cfg!(windows) { "dsh.exe" } else { "dsh" });
    let command_uses_bundled = existing
        .as_ref()
        .map(|path| same_file(path, &bundled))
        .unwrap_or(false);
    let conflict = existing
        .as_ref()
        .map(|path| !same_file(path, &bundled))
        .unwrap_or(false);
    let path_configured = command_uses_bundled || shell_profile_has_cli_path();
    let managed_active = launcher_installed && path_configured;
    serde_json::json!({
        "bundledReady": bundled.is_file(),
        "bundledPath": bundled,
        "managed": managed_active,
        "launcherInstalled": launcher_installed,
        "managedPath": managed,
        "commandPath": existing,
        "conflict": conflict,
        "pathConfigured": path_configured,
        "requiresNewTerminal": managed_active && !command_uses_bundled,
        "version": bundled_dsh_version(),
        "profilePath": harness_paths().dsh_home.join("profiles/web"),
    })
}

fn install_cli_launcher(replace: bool) -> Result<serde_json::Value, String> {
    let bundled = bundled_cli_path();
    if !bundled.is_file() {
        return Err("当前安装包缺少内置 dsh 命令启动器，请重新安装桌面应用。".into());
    }
    let managed = managed_cli_path();
    let command = if cfg!(windows) { "dsh.exe" } else { "dsh" };
    let existing_conflict = command_on_path(command)
        .map(|path| !same_file(&path, &bundled))
        .unwrap_or(false);
    if managed.exists() && !same_file(&managed, &bundled) {
        if !replace {
            return Err(format!(
                "{} 已存在其他 dsh 命令；只有明确选择替换后才会改用桌面版。",
                managed.display()
            ));
        }
        fs::remove_file(&managed)
            .map_err(|error| format!("无法替换 {}：{error}", managed.display()))?;
    }
    if let Some(existing) = command_on_path(command) {
        if !same_file(&existing, &bundled) && !replace {
            return Err(format!(
                "已检测到其他 dsh 命令：{}。请选择“改用桌面版”后再继续。",
                existing.display()
            ));
        }
    }
    let parent = managed.parent().ok_or("invalid managed CLI path")?;
    fs::create_dir_all(parent)
        .map_err(|error| format!("无法创建 {}：{error}", parent.display()))?;
    if !managed.exists() {
        #[cfg(unix)]
        std::os::unix::fs::symlink(&bundled, &managed)
            .map_err(|error| format!("无法安装 {}：{error}", managed.display()))?;
        #[cfg(not(unix))]
        fs::copy(&bundled, &managed)
            .map_err(|error| format!("无法安装 {}：{error}", managed.display()))?;
    }
    let profile_updated = ensure_shell_cli_path(replace && existing_conflict)?;
    let mut status = cli_status_value();
    status["profileUpdated"] = serde_json::Value::Bool(profile_updated);
    Ok(status)
}

fn remove_cli_launcher() -> Result<serde_json::Value, String> {
    let managed = managed_cli_path();
    let bundled = bundled_cli_path();
    if managed.exists() {
        if !same_file(&managed, &bundled) {
            return Err(format!(
                "{} 不是桌面版管理的命令，因此没有删除。",
                managed.display()
            ));
        }
        fs::remove_file(&managed)
            .map_err(|error| format!("无法移除 {}：{error}", managed.display()))?;
    }
    remove_shell_cli_path()?;
    Ok(cli_status_value())
}

fn runtime_path_env() -> Result<OsString, String> {
    let mut entries = Vec::new();
    let node = resolve_node();
    if let Some(parent) = node.parent().filter(|path| !path.as_os_str().is_empty()) {
        entries.push(parent.to_path_buf());
    }
    entries.push(resolve_modules_directory().join(".bin"));
    if let Some(existing) = env::var_os("PATH") {
        entries.extend(env::split_paths(&existing));
    }
    env::join_paths(entries).map_err(|error| format!("failed to construct runtime PATH: {error}"))
}

fn apply_harness_environment(command: &mut Command, paths: &HarnessPaths) -> Result<(), String> {
    command
        .env("HOME", &paths.home)
        .env("DSH_HOME", &paths.dsh_home)
        .env("PATH", runtime_path_env()?);
    Ok(())
}

fn apply_noninteractive_pnpm_environment(command: &mut Command) {
    // Desktop actions never have a TTY. pnpm may otherwise pause to confirm
    // rebuilding node_modules, which aborts both installation and rollback.
    command
        .env("CI", "true")
        .env("PNPM_CONFIG_CONFIRM_MODULES_PURGE", "false")
        .env("npm_config_confirm_modules_purge", "false");
}

fn plugin_output_tail(output: &[u8]) -> String {
    let text = String::from_utf8_lossy(output);
    let lines: Vec<String> = text
        .lines()
        .rev()
        .take(40)
        .map(redact_startup_line)
        .collect();
    lines.into_iter().rev().collect::<Vec<_>>().join("\n")
}

fn run_plugin_command(action: &str, arguments: &[&str], failure_label: &str) -> Result<(), String> {
    let pnpm = bundled_pnpm_path();
    if !pnpm.is_file() {
        return Err(format!("桌面安装包缺少内置 pnpm：{}", pnpm.display()));
    }
    let paths = harness_paths();
    let node = resolve_node();
    let script = resolve_script();
    let mut command = Command::new(node);
    command
        .arg("--expose-internals")
        .arg(script)
        .args(["plugin", "--profile", "web", action])
        .args(arguments)
        .current_dir(&paths.home)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    apply_harness_environment(&mut command, &paths)?;
    apply_noninteractive_pnpm_environment(&mut command);
    let output = command
        .output()
        .map_err(|error| format!("无法启动插件安装器：{error}"))?;
    if output.status.success() {
        return Ok(());
    }
    let mut details = plugin_output_tail(&output.stderr);
    if details.is_empty() {
        details = plugin_output_tail(&output.stdout);
    }
    Err(if details.is_empty() {
        format!("{failure_label}（{}）。", output.status)
    } else {
        format!("{failure_label}（{}）：\n{details}", output.status)
    })
}

fn run_plugin_add(spec: &str) -> Result<(), String> {
    run_plugin_command("add", &[spec], "插件安装失败")
}

fn run_plugin_remove(name: &str) -> Result<(), String> {
    run_plugin_command("remove", &[name], "插件移除失败")
}

fn sync_profile_modules_after_restore(dsh_home: &Path) -> Result<(), String> {
    let pnpm = bundled_pnpm_script();
    if !pnpm.is_file() {
        return Err(format!("桌面安装包缺少内置 pnpm：{}", pnpm.display()));
    }
    let paths = harness_paths();
    let profile = dsh_home.join("profiles/web");
    let mut command = Command::new(resolve_node());
    command
        .arg(pnpm)
        .arg("install")
        .arg("--offline")
        .current_dir(&profile)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    if profile.join("pnpm-lock.yaml").is_file() {
        command.arg("--frozen-lockfile");
    }
    apply_harness_environment(&mut command, &paths)?;
    apply_noninteractive_pnpm_environment(&mut command);
    let output = command
        .output()
        .map_err(|error| format!("无法同步回滚后的插件依赖：{error}"))?;
    if output.status.success() {
        return Ok(());
    }
    let mut details = plugin_output_tail(&output.stderr);
    if details.is_empty() {
        details = plugin_output_tail(&output.stdout);
    }
    Err(if details.is_empty() {
        format!("回滚后的插件依赖同步失败（{}）。", output.status)
    } else {
        format!("回滚后的插件依赖同步失败（{}）：\n{details}", output.status)
    })
}

fn spawn_harness(mode: LaunchMode) -> Result<Child, String> {
    let node = resolve_node();
    let script = resolve_script();
    let paths = harness_paths();
    ensure_desktop_settings_module_link(&paths.dsh_home)?;
    let desktop_patch = desktop_settings_patch_path();
    if !desktop_patch.is_file() {
        return Err(format!(
            "桌面安装包缺少 Settings 插件扩展：{}",
            desktop_patch.display()
        ));
    }
    if mode == LaunchMode::Safe {
        prepare_safe_profile(&paths.dsh_home)?;
    }

    // The harness is spawned with `current_dir(home)`, and macOS refuses to
    // start a child whose working directory does not exist (ENOENT). That used
    // to surface as a setup error -> tauri panic -> abort() (panic = "abort"
    // in the release profile), so create the directory (and any missing
    // parents) up front so a missing SPIKE_HOME/HOME cannot abort startup.
    fs::create_dir_all(&paths.home).map_err(|error| {
        format!(
            "failed to create harness home directory {}: {error}",
            paths.home.display()
        )
    })?;

    println!(
        "[dsh] node={} script={} home={} profile={}",
        node.display(),
        script.display(),
        paths.home.display(),
        mode.profile_name()
    );
    let mut command = Command::new(&node);
    command.arg("--expose-internals").arg(&script);
    match mode {
        LaunchMode::Normal => {
            command.args(["--profile", "web"]);
        }
        LaunchMode::Safe => {
            command.args(["--profile", SAFE_PROFILE_NAME]);
        }
    }
    command.arg("--patch").arg(&desktop_patch);
    command
        .args(["--host", "127.0.0.1", "--port", "0", "--no-open"])
        .current_dir(&paths.home)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    apply_harness_environment(&mut command, &paths)?;
    #[cfg(unix)]
    command.process_group(0);
    command
        .spawn()
        .map_err(|error| format!("failed to spawn {}: {error}", node.display()))
}

fn parse_readiness(line: &str) -> Option<tauri::Url> {
    let raw = line.trim().strip_prefix(READINESS_MARK)?.trim();
    let url: tauri::Url = raw.parse().ok()?;
    let valid = url.scheme() == "http"
        && url.host_str() == Some("127.0.0.1")
        && url.port().is_some()
        && url.username().is_empty()
        && url.password().is_none()
        && url.query().is_none()
        && url.fragment().is_none();
    valid.then_some(url)
}

fn wait_readiness(child: &mut Child) -> Result<(tauri::Url, StartupTail), String> {
    let stdout = child.stdout.take().ok_or("no stdout pipe")?;
    let stderr = child.stderr.take().ok_or("no stderr pipe")?;
    let (sender, receiver) = mpsc::channel::<Result<tauri::Url, String>>();
    let tail: StartupTail = Arc::new(Mutex::new(VecDeque::new()));

    let stderr_tail = Arc::clone(&tail);
    thread::spawn(move || {
        let reader = BufReader::new(stderr);
        for line in reader.lines() {
            match line {
                Ok(value) => {
                    let safe = record_startup_line(&stderr_tail, "stderr", &value);
                    eprintln!("[dsh:err] {safe}");
                }
                Err(_) => break,
            }
        }
    });

    let stdout_tail = Arc::clone(&tail);
    thread::spawn(move || {
        let mut sent = false;
        let reader = BufReader::new(stdout);
        for line in reader.lines() {
            let line = match line {
                Ok(value) => value,
                Err(_) => break,
            };
            let safe = record_startup_line(&stdout_tail, "stdout", &line);
            println!("[dsh:out] {safe}");
            if !sent {
                if let Some(url) = parse_readiness(&line) {
                    let _ = sender.send(Ok(url));
                    sent = true;
                }
            }
        }
        if !sent {
            // stderr normally closes alongside stdout; leave a short window for
            // its reader to append the actionable loader error before reporting.
            thread::sleep(Duration::from_millis(50));
            let _ = sender.send(Err("dsh stdout closed before readiness".into()));
        }
    });

    let received = receiver.recv_timeout(STARTUP_TIMEOUT).map_err(|error| {
        format!(
            "timed out waiting for dsh readiness: {error}{}",
            startup_tail_text(&tail)
        )
    })?;
    let url = received.map_err(|error| format!("{error}{}", startup_tail_text(&tail)))?;
    thread::sleep(READINESS_GRACE);
    if let Some(status) = child
        .try_wait()
        .map_err(|error| format!("failed to inspect dsh after readiness: {error}"))?
    {
        return Err(format!(
            "dsh exited immediately after readiness: {status}{}",
            startup_tail_text(&tail)
        ));
    }
    Ok((url, tail))
}

fn acknowledge_onboarding(origin: &tauri::Url) -> Result<(), String> {
    let output = Command::new(resolve_node())
        .arg(resolve_onboarding_helper())
        .arg(origin.as_str())
        .arg(resolve_modules_directory())
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .output()
        .map_err(|error| format!("failed to start onboarding helper: {error}"))?;
    if output.status.success() {
        return Ok(());
    }
    let stderr = String::from_utf8_lossy(&output.stderr);
    Err(format!(
        "onboarding helper failed with {}: {}",
        output.status,
        stderr.trim()
    ))
}

fn is_recovery_asset_url(url: &tauri::Url) -> bool {
    url.scheme() == "tauri" || url.host_str() == Some("tauri.localhost")
}

fn recovery_page_url() -> Result<tauri::Url, String> {
    #[cfg(windows)]
    let raw = "http://tauri.localhost/index.html";
    #[cfg(not(windows))]
    let raw = "tauri://localhost/index.html";
    raw.parse()
        .map_err(|error| format!("failed to resolve recovery page URL: {error}"))
}

fn emit_bridge_event(handle: &tauri::AppHandle, event: &str, payload: serde_json::Value) {
    let detail = serde_json::json!({ "type": event, "payload": payload });
    let Ok(detail) = serde_json::to_string(&detail) else {
        return;
    };
    if let Some(window) = handle.get_webview_window("main") {
        let script = format!(
            "window.dispatchEvent(new CustomEvent('dsh-desktop-event', {{ detail: {detail} }}));"
        );
        if let Err(error) = window.eval(script) {
            eprintln!("[dsh] failed to emit desktop bridge event: {error}");
        }
    }
}

fn usage_record_from_event(value: &serde_json::Value, cutoff_ms: u64) -> Option<serde_json::Value> {
    if value.get("type")?.as_str()? != "assistant/message" {
        return None;
    }
    let time = value.get("time")?.as_u64()?;
    if time < cutoff_ms {
        return None;
    }
    let data = value.get("data")?;
    let usage = data.get("usage")?;
    let message = data.get("message")?;
    let source = message.get("source");
    let token = |name: &str| {
        usage
            .get(name)
            .and_then(serde_json::Value::as_u64)
            .unwrap_or(0)
    };
    Some(serde_json::json!({
        "id": message.get("id")?.as_str()?,
        "time": time,
        "provider": source.and_then(|value| value.get("provider")).and_then(serde_json::Value::as_str).unwrap_or(""),
        "model": source.and_then(|value| value.get("model")).and_then(serde_json::Value::as_str).unwrap_or(""),
        "usage": {
            "inputTokens": token("inputTokens"),
            "outputTokens": token("outputTokens"),
            "cacheReadTokens": token("cacheReadTokens"),
            "cacheWriteTokens": token("cacheWriteTokens"),
        }
    }))
}

fn collect_usage_log_paths(directory: &Path, cutoff_ms: u64, paths: &mut Vec<PathBuf>) {
    let Ok(entries) = fs::read_dir(directory) else {
        return;
    };
    for entry in entries.flatten() {
        let Ok(file_type) = entry.file_type() else {
            continue;
        };
        if file_type.is_symlink() {
            continue;
        }
        let path = entry.path();
        if file_type.is_dir() {
            collect_usage_log_paths(&path, cutoff_ms, paths);
            continue;
        }
        if !file_type.is_file() {
            continue;
        }
        let Some(name) = path.file_name().and_then(|value| value.to_str()) else {
            continue;
        };
        if !matches!(name, "session.jsonl" | "session.jsonl.zstd") {
            continue;
        }
        let modified_ms = entry
            .metadata()
            .and_then(|metadata| metadata.modified())
            .ok()
            .and_then(|modified| modified.duration_since(UNIX_EPOCH).ok())
            .map(|duration| duration.as_millis() as u64);
        if modified_ms.is_none_or(|modified| modified >= cutoff_ms) {
            paths.push(path);
        }
    }
}

fn scan_usage_log(
    path: &Path,
    cutoff_ms: u64,
    records: &mut Vec<serde_json::Value>,
) -> Result<(), String> {
    let file = fs::File::open(path)
        .map_err(|error| format!("failed to open {}: {error}", path.display()))?;
    let mut reader: Box<dyn BufRead> =
        if path.extension().and_then(|value| value.to_str()) == Some("zstd") {
            let decoder = zstd::stream::read::Decoder::new(file)
                .map_err(|error| format!("failed to decode {}: {error}", path.display()))?;
            Box::new(BufReader::new(decoder))
        } else {
            Box::new(BufReader::new(file))
        };
    let mut line = String::new();
    loop {
        line.clear();
        let read = reader
            .read_line(&mut line)
            .map_err(|error| format!("failed to read {}: {error}", path.display()))?;
        if read == 0 {
            break;
        }
        if !line.contains("assistant/message") {
            continue;
        }
        let value: serde_json::Value = serde_json::from_str(&line)
            .map_err(|error| format!("failed to parse {}: {error}", path.display()))?;
        if let Some(record) = usage_record_from_event(&value, cutoff_ms) {
            records.push(record);
        }
    }
    Ok(())
}

fn usage_snapshot_value(cutoff_ms: u64) -> serde_json::Value {
    let sessions = harness_paths().dsh_home.join("sessions");
    let mut paths = Vec::new();
    collect_usage_log_paths(&sessions, cutoff_ms, &mut paths);
    let mut records = Vec::new();
    let mut warnings = 0_u64;
    for path in &paths {
        if let Err(error) = scan_usage_log(path, cutoff_ms, &mut records) {
            warnings += 1;
            eprintln!("[dsh] usage scan warning: {error}");
        }
    }
    records.sort_by_key(|record| {
        record
            .get("time")
            .and_then(serde_json::Value::as_u64)
            .unwrap_or(0)
    });
    serde_json::json!({
        "records": records,
        "warnings": warnings,
        "scannedFiles": paths.len(),
        "scannedAt": SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_millis(),
    })
}

fn desktop_status_value() -> Result<serde_json::Value, String> {
    let mut status = plugin_manager_status_value()?;
    status["cli"] = cli_status_value();
    status["profilePath"] = serde_json::Value::String(
        harness_paths()
            .dsh_home
            .join("profiles/web")
            .display()
            .to_string(),
    );
    Ok(status)
}

fn emit_action_error(handle: &tauri::AppHandle, error: impl Into<String>) {
    emit_bridge_event(
        handle,
        "operation-error",
        serde_json::json!({ "message": error.into() }),
    );
}

fn handle_desktop_action(handle: tauri::AppHandle, destination: &tauri::Url) {
    if destination.host_str() != Some("action") {
        return;
    }
    let parameters: BTreeMap<String, String> = destination.query_pairs().into_owned().collect();
    if parameters.get("token") != Some(&*DESKTOP_ACTION_TOKEN) {
        eprintln!("[dsh] rejected desktop action with an invalid token");
        return;
    }
    let action = destination.path().trim_start_matches('/');
    match action {
        "usage-snapshot" => {
            let Some(cutoff_ms) = parameters
                .get("cutoff")
                .and_then(|value| value.parse::<u64>().ok())
            else {
                emit_bridge_event(
                    &handle,
                    "usage-snapshot-error",
                    serde_json::json!({ "message": "invalid usage cutoff" }),
                );
                return;
            };
            let now_ms = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_millis() as u64;
            let oldest_allowed = now_ms.saturating_sub(31 * 24 * 60 * 60 * 1_000);
            if cutoff_ms < oldest_allowed || cutoff_ms > now_ms.saturating_add(60_000) {
                emit_bridge_event(
                    &handle,
                    "usage-snapshot-error",
                    serde_json::json!({ "message": "usage cutoff is outside the allowed range" }),
                );
                return;
            }
            thread::spawn(move || {
                let snapshot = usage_snapshot_value(cutoff_ms);
                emit_bridge_event(&handle, "usage-snapshot", snapshot);
            });
        }
        "sync-theme" => {
            let theme = match parameters.get("scheme").map(String::as_str) {
                Some("light") => Theme::Light,
                Some("dark") => Theme::Dark,
                _ => {
                    eprintln!("[dsh] ignored invalid desktop theme");
                    return;
                }
            };
            let color = ["red", "green", "blue"].map(|channel| {
                parameters
                    .get(channel)
                    .and_then(|value| value.parse::<u8>().ok())
            });
            if let Some(window) = handle.get_webview_window("main") {
                if let Err(error) = window.set_theme(Some(theme)) {
                    eprintln!("[dsh] failed to sync native theme: {error}");
                }
                if let [Some(red), Some(green), Some(blue)] = color {
                    if let Err(error) = window
                        .set_background_color(Some(tauri::webview::Color(red, green, blue, 255)))
                    {
                        eprintln!("[dsh] failed to sync native background: {error}");
                    }
                }
            }
        }
        "set-smooth-stream" => {
            let enabled = match parameters.get("enabled").map(String::as_str) {
                Some("1") => true,
                Some("0") => false,
                _ => {
                    emit_bridge_event(
                        &handle,
                        "smooth-stream-setting-error",
                        serde_json::json!({
                            "enabled": smooth_stream_enabled_at(&desktop_preferences_path(&harness_paths().dsh_home)),
                            "message": "invalid smooth stream preference"
                        }),
                    );
                    return;
                }
            };
            let path = desktop_preferences_path(&harness_paths().dsh_home);
            match write_smooth_stream_preference(&path, enabled) {
                Ok(()) => emit_bridge_event(
                    &handle,
                    "smooth-stream-setting",
                    serde_json::json!({ "enabled": enabled }),
                ),
                Err(error) => emit_bridge_event(
                    &handle,
                    "smooth-stream-setting-error",
                    serde_json::json!({
                        "enabled": smooth_stream_enabled_at(&path),
                        "message": error
                    }),
                ),
            }
        }
        "status" => match desktop_status_value() {
            Ok(status) => emit_bridge_event(&handle, "desktop-status", status),
            Err(error) => emit_action_error(&handle, error),
        },
        "install-plugin" => {
            let Some(spec) = parameters.get("spec").cloned() else {
                emit_action_error(&handle, "请输入插件包名或 GitHub 地址。");
                return;
            };
            emit_bridge_event(
                &handle,
                "operation-started",
                serde_json::json!({ "operation": "install-plugin" }),
            );
            thread::spawn(move || match perform_plugin_install(spec) {
                Ok(status) => emit_bridge_event(&handle, "plugin-installed", status),
                Err(error) => emit_action_error(&handle, error),
            });
        }
        "remove-plugin" => {
            let Some(name) = parameters.get("name").cloned() else {
                emit_action_error(&handle, "请选择要移除的插件。");
                return;
            };
            emit_bridge_event(
                &handle,
                "operation-started",
                serde_json::json!({ "operation": "remove-plugin" }),
            );
            thread::spawn(move || match perform_plugin_remove(name) {
                Ok(status) => emit_bridge_event(&handle, "plugin-removed", status),
                Err(error) => emit_action_error(&handle, error),
            });
        }
        "restart-harness" => {
            emit_bridge_event(
                &handle,
                "operation-started",
                serde_json::json!({ "operation": "restart-harness" }),
            );
            thread::spawn(move || {
                if let Err(error) = perform_plugin_restart(handle.clone()) {
                    emit_action_error(&handle, error);
                }
            });
        }
        "install-cli" => {
            let replace = parameters.get("replace").map(String::as_str) == Some("1");
            emit_bridge_event(
                &handle,
                "operation-started",
                serde_json::json!({ "operation": "install-cli" }),
            );
            thread::spawn(move || match install_cli_launcher(replace) {
                Ok(status) => emit_bridge_event(&handle, "cli-status", status),
                Err(error) => emit_action_error(&handle, error),
            });
        }
        "remove-cli" => {
            emit_bridge_event(
                &handle,
                "operation-started",
                serde_json::json!({ "operation": "remove-cli" }),
            );
            thread::spawn(move || match remove_cli_launcher() {
                Ok(status) => emit_bridge_event(&handle, "cli-status", status),
                Err(error) => emit_action_error(&handle, error),
            });
        }
        _ => eprintln!("[dsh] ignored unknown desktop action: {action}"),
    }
}

fn build_main_window(
    handle: &tauri::AppHandle,
    url: WebviewUrl,
    recovery: bool,
) -> Result<(), String> {
    let navigation_handle = handle.clone();
    let updater_script = UPDATER_SCRIPT.replace("__DSH_CURRENT_VERSION__", SHELL_VERSION);
    let recovery_bridge_script = RECOVERY_BRIDGE_SCRIPT
        .replace("__DSH_RECOVERY_URL__", recovery_page_url()?.as_str())
        .replace("__DSH_ACTION_TOKEN__", &DESKTOP_ACTION_TOKEN);
    let theme_sync_script =
        THEME_SYNC_SCRIPT.replace("__DSH_ACTION_TOKEN__", &DESKTOP_ACTION_TOKEN);
    let usage_meter_script =
        USAGE_METER_SCRIPT.replace("__DSH_ACTION_TOKEN__", &DESKTOP_ACTION_TOKEN);
    let smooth_stream_enabled =
        smooth_stream_enabled_at(&desktop_preferences_path(&harness_paths().dsh_home));
    let smooth_stream_script = SMOOTH_STREAM_SCRIPT
        .replace(
            "__DSH_SMOOTH_STREAM_ENABLED__",
            if smooth_stream_enabled {
                "true"
            } else {
                "false"
            },
        )
        .replace("__DSH_ACTION_TOKEN__", &DESKTOP_ACTION_TOKEN);
    let (title, width, height, min_width, min_height) = if recovery {
        (RECOVERY_TITLE, 820.0, 680.0, 640.0, 520.0)
    } else {
        (PRODUCT_NAME, 1440.0, 900.0, 960.0, 640.0)
    };
    let builder = WebviewWindowBuilder::new(handle, "main", url)
        .title(title)
        .inner_size(width, height)
        .min_inner_size(min_width, min_height)
        .initialization_script(updater_script)
        .initialization_script(recovery_bridge_script)
        .initialization_script(theme_sync_script)
        .initialization_script(usage_meter_script)
        .initialization_script(smooth_stream_script)
        .on_navigation(move |destination| {
            if destination.scheme() == "dsh-desktop" {
                handle_desktop_action(navigation_handle.clone(), destination);
                return false;
            }
            if is_recovery_asset_url(destination) {
                if destination.path().ends_with("index.html") {
                    if let Some(window) = navigation_handle.get_webview_window("main") {
                        let _ = window.set_title(RECOVERY_TITLE);
                        let _ = window.set_min_size(Some(tauri::LogicalSize::new(640.0, 520.0)));
                        let _ = window.set_size(tauri::LogicalSize::new(820.0, 680.0));
                    }
                }
                return true;
            }
            let allowed = ALLOWED_HARNESS_ORIGIN
                .lock()
                .ok()
                .and_then(|origin| origin.clone());
            if allowed.as_deref() == Some(&destination.origin().ascii_serialization()) {
                return true;
            }
            if matches!(destination.scheme(), "http" | "https" | "mailto") {
                println!("[dsh] external navigation: {destination}");
                let _ = navigation_handle
                    .opener()
                    .open_url(destination.as_str(), None::<&str>);
            }
            false
        });
    #[cfg(target_os = "macos")]
    let builder = if recovery {
        builder.title_bar_style(tauri::TitleBarStyle::Transparent)
    } else {
        builder
            .title_bar_style(tauri::TitleBarStyle::Overlay)
            .hidden_title(true)
    };
    let window = builder
        .build()
        .map_err(|error| format!("failed to create desktop window: {error}"))?;
    window
        .show()
        .map_err(|error| format!("failed to show desktop window: {error}"))?;
    window
        .set_focus()
        .map_err(|error| format!("failed to focus desktop window: {error}"))?;
    println!("[dsh] window created");
    Ok(())
}

fn show_recovery_window(handle: &tauri::AppHandle) -> Result<(), String> {
    if let Ok(mut origin) = ALLOWED_HARNESS_ORIGIN.lock() {
        *origin = None;
    }
    if let Some(window) = handle.get_webview_window("main") {
        window
            .navigate(recovery_page_url()?)
            .map_err(|error| format!("failed to open recovery page: {error}"))?;
        let _ = window.set_title(RECOVERY_TITLE);
        let _ = window.set_min_size(Some(tauri::LogicalSize::new(640.0, 520.0)));
        let _ = window.set_size(tauri::LogicalSize::new(820.0, 680.0));
        let _ = window.show();
        let _ = window.set_focus();
    } else {
        build_main_window(handle, WebviewUrl::App("index.html".into()), true)?;
    }
    println!("[dsh] recovery window ready");
    Ok(())
}

fn show_harness_window(
    handle: &tauri::AppHandle,
    mut url: tauri::Url,
    mode: LaunchMode,
    notice: Option<HarnessNotice>,
) -> Result<(), String> {
    if let Ok(mut current) = CURRENT_HARNESS_URL.lock() {
        *current = Some(url.as_str().to_string());
    }
    if mode == LaunchMode::Safe {
        url.query_pairs_mut()
            .append_pair("dsh-desktop-safe-mode", "1");
    }
    if let Some(notice) = notice {
        let (key, value) = match notice {
            HarnessNotice::InstallVerifying(value) => ("dsh-desktop-plugin-verifying", value),
            HarnessNotice::InstallRolledBack(value) => ("dsh-desktop-plugin-rollback", value),
        };
        url.query_pairs_mut().append_pair(key, &value);
    }
    if let Ok(mut origin) = ALLOWED_HARNESS_ORIGIN.lock() {
        *origin = Some(url.origin().ascii_serialization());
    }
    if let Some(window) = handle.get_webview_window("main") {
        window
            .navigate(url)
            .map_err(|error| format!("failed to open Harness: {error}"))?;
        let _ = window.set_title(PRODUCT_NAME);
        let _ = window.set_min_size(Some(tauri::LogicalSize::new(960.0, 640.0)));
        let _ = window.set_size(tauri::LogicalSize::new(1440.0, 900.0));
        let _ = window.show();
        let _ = window.set_focus();
    } else {
        build_main_window(handle, WebviewUrl::External(url), false)?;
    }
    Ok(())
}

fn start_harness(mode: LaunchMode) -> Result<(Child, tauri::Url, StartupTail), String> {
    let mut child = spawn_harness(mode)?;
    println!("[dsh] harness spawned (pid {})", child.id());
    let (url, tail) = match wait_readiness(&mut child) {
        Ok(value) => value,
        Err(error) => {
            terminate_child(&mut child);
            return Err(error);
        }
    };
    println!("[dsh] harness ready at {url}");
    match acknowledge_onboarding(&url) {
        Ok(()) => println!("[dsh] upstream welcome notice acknowledged"),
        Err(error) => eprintln!("[dsh] warning: {error}"),
    }
    Ok((child, url, tail))
}

fn pending_packages(value: &serde_json::Value) -> Vec<String> {
    value["packages"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(serde_json::Value::as_str)
        .map(str::to_string)
        .collect()
}

fn rollback_pending_install(dsh_home: &Path) -> Result<String, String> {
    let pending = read_pending_install(dsh_home)?.ok_or("没有等待验证的插件安装事务。")?;
    let label = pending_install_label(&pending);
    let snapshot = pending["rollbackSnapshot"]
        .as_str()
        .unwrap_or(BEFORE_PLUGIN_INSTALL);
    restore_profile_snapshot(dsh_home, snapshot, None)?;
    sync_profile_modules_after_restore(dsh_home)?;
    clear_pending_install(dsh_home)?;
    println!("[dsh] rolled back pending plugin change: {label}");
    Ok(label)
}

fn launch_normal_with_pending_fallback(handle: &tauri::AppHandle) -> Result<(), String> {
    let paths = harness_paths();
    detect_external_change_before_launch(&paths.dsh_home)?;
    let pending = read_pending_install(&paths.dsh_home)?;
    let mut notice = None;
    let mut should_fallback = false;

    if let Some(transaction) = pending.as_ref() {
        let label = pending_install_label(transaction);
        if transaction["state"].as_str() == Some("installing") {
            rollback_pending_install(&paths.dsh_home)?;
            notice = Some(HarnessNotice::InstallRolledBack(label));
        } else {
            rewrite_pending_state(&paths.dsh_home, transaction, "verifying")?;
            notice = Some(HarnessNotice::InstallVerifying(label));
            should_fallback = true;
        }
    }

    match start_harness(LaunchMode::Normal) {
        Ok((child, url, tail)) => {
            register_harness(handle, child, LaunchMode::Normal, tail)?;
            show_harness_window(handle, url, LaunchMode::Normal, notice)
        }
        Err(first_error) if should_fallback => {
            let label = rollback_pending_install(&paths.dsh_home).map_err(|rollback_error| {
                format!(
                    "新插件启动失败，自动回滚也未完成。\n启动错误：{first_error}\n回滚错误：{rollback_error}"
                )
            })?;
            let (child, url, tail) = start_harness(LaunchMode::Normal).map_err(|rollback_error| {
                format!(
                    "新插件启动失败；profile 已回滚，但 Harness 仍无法启动。\n首次错误：{first_error}\n回滚后错误：{rollback_error}"
                )
            })?;
            register_harness(handle, child, LaunchMode::Normal, tail)?;
            show_harness_window(
                handle,
                url,
                LaunchMode::Normal,
                Some(HarnessNotice::InstallRolledBack(label)),
            )
        }
        Err(error) => Err(error),
    }
}

fn rollback_runtime_plugin_failure(handle: &tauri::AppHandle, first_error: &str) -> bool {
    let paths = harness_paths();
    let Ok(Some(_)) = read_pending_install(&paths.dsh_home) else {
        return false;
    };
    let Ok(_operation) = OperationGuard::acquire() else {
        return false;
    };
    stop_managed_child();
    let result = rollback_pending_install(&paths.dsh_home).and_then(|label| {
        let (child, url, tail) = start_harness(LaunchMode::Normal)?;
        register_harness(handle, child, LaunchMode::Normal, tail)?;
        show_harness_window(
            handle,
            url,
            LaunchMode::Normal,
            Some(HarnessNotice::InstallRolledBack(label)),
        )
    });
    if let Err(error) = result {
        let message = format!(
            "新插件在验证期间退出，自动回滚后仍无法启动。\n插件错误：{first_error}\n回滚后错误：{error}"
        );
        eprintln!("[dsh] plugin rollback failed: {message}");
        set_recovery_state("failed", message, false);
        let _ = show_recovery_window(handle);
    }
    true
}

fn start_child_monitor(
    handle: tauri::AppHandle,
    generation: u64,
    mode: LaunchMode,
    tail: StartupTail,
) {
    thread::spawn(move || {
        let ready_at = Instant::now();
        let mut snapshot_attempted = mode == LaunchMode::Safe;
        loop {
            thread::sleep(MONITOR_INTERVAL);
            if CHILD_GENERATION.load(Ordering::SeqCst) != generation {
                return;
            }
            let status = match CHILD.lock() {
                Ok(mut guard) => match guard.as_mut() {
                    Some(child) => child.try_wait(),
                    None => return,
                },
                Err(_) => Err(std::io::Error::other("harness supervisor lock poisoned")),
            };
            match status {
                Ok(Some(exit)) => {
                    if let Ok(mut child) = CHILD.lock() {
                        *child = None;
                    }
                    if CHILD_GENERATION.load(Ordering::SeqCst) != generation {
                        return;
                    }
                    let error = format!(
                        "Harness exited after startup: {exit}{}",
                        startup_tail_text(&tail)
                    );
                    eprintln!("[dsh] runtime failed: {error}");
                    if mode == LaunchMode::Normal
                        && ready_at.elapsed() < SNAPSHOT_STABILITY
                        && rollback_runtime_plugin_failure(&handle, &error)
                    {
                        return;
                    }
                    set_recovery_state("failed", error, mode == LaunchMode::Safe);
                    if let Err(error) = show_recovery_window(&handle) {
                        eprintln!("[dsh] failed to show runtime recovery: {error}");
                    }
                    return;
                }
                Ok(None) => {
                    if !snapshot_attempted && ready_at.elapsed() >= SNAPSHOT_STABILITY {
                        let paths = harness_paths();
                        if read_pending_install(&paths.dsh_home)
                            .ok()
                            .flatten()
                            .and_then(|pending| pending["state"].as_str().map(str::to_string))
                            .as_deref()
                            == Some("restart-required")
                        {
                            continue;
                        }
                        snapshot_attempted = true;
                        match write_profile_snapshot(&paths.dsh_home, "last-known-good") {
                            Ok(()) => {
                                println!("[dsh] last-known-good profile snapshot saved");
                                if let Some(pending) =
                                    read_pending_install(&paths.dsh_home).ok().flatten()
                                {
                                    let label = pending_install_label(&pending);
                                    let outcome = pending_change_outcome(&pending);
                                    match clear_pending_install(&paths.dsh_home) {
                                        Ok(()) => {
                                            println!("[dsh] plugin change verified");
                                            emit_bridge_event(
                                                &handle,
                                                "plugin-verified",
                                                serde_json::json!({
                                                    "label": label,
                                                    "outcome": outcome,
                                                }),
                                            );
                                        }
                                        Err(error) => eprintln!("[dsh] warning: {error}"),
                                    }
                                }
                            }
                            Err(error) => eprintln!("[dsh] warning: {error}"),
                        }
                    }
                }
                Err(error) => {
                    let message = format!("failed to monitor Harness after startup: {error}");
                    eprintln!("[dsh] runtime monitor failed: {message}");
                    set_recovery_state("failed", message, mode == LaunchMode::Safe);
                    if let Err(error) = show_recovery_window(&handle) {
                        eprintln!("[dsh] failed to show monitor recovery: {error}");
                    }
                    return;
                }
            }
        }
    });
}

fn register_harness(
    handle: &tauri::AppHandle,
    child: Child,
    mode: LaunchMode,
    tail: StartupTail,
) -> Result<(), String> {
    let generation = CHILD_GENERATION.fetch_add(1, Ordering::SeqCst) + 1;
    *CHILD
        .lock()
        .map_err(|_| "harness supervisor lock poisoned".to_string())? = Some(child);
    set_recovery_state(
        if mode == LaunchMode::Safe {
            "safe-mode"
        } else {
            "running"
        },
        "",
        mode == LaunchMode::Safe,
    );
    if mode == LaunchMode::Normal {
        if let Ok(state) = read_plugin_state(&harness_paths().dsh_home) {
            if let Ok(mut loaded) = LOADED_PLUGIN_STATE.lock() {
                *loaded = Some(state);
            }
        }
    }
    start_child_monitor(handle.clone(), generation, mode, tail);
    println!("[dsh] harness registered under supervisor (generation {generation})");
    Ok(())
}

fn start_profile_watcher(handle: tauri::AppHandle) {
    if PROFILE_WATCHER_STARTED.swap(true, Ordering::SeqCst) {
        return;
    }
    thread::spawn(move || {
        let paths = harness_paths();
        let mut candidate = String::new();
        let mut stable_polls = 0_u8;
        loop {
            thread::sleep(PROFILE_WATCH_INTERVAL);
            if OPERATION_ACTIVE.load(Ordering::SeqCst) {
                candidate.clear();
                stable_polls = 0;
                continue;
            }
            if read_pending_install(&paths.dsh_home)
                .ok()
                .flatten()
                .is_some()
            {
                candidate.clear();
                stable_polls = 0;
                continue;
            }
            let before = LOADED_PLUGIN_STATE
                .lock()
                .ok()
                .and_then(|state| state.clone());
            let Some(before) = before else {
                continue;
            };
            let Ok(after) = read_plugin_state(&paths.dsh_home) else {
                continue;
            };
            let before_fingerprint = plugin_state_fingerprint(&before);
            let after_fingerprint = plugin_state_fingerprint(&after);
            if before_fingerprint == after_fingerprint {
                candidate.clear();
                stable_polls = 0;
                continue;
            }
            if !profile_dependencies_ready(&paths.dsh_home, &after) {
                candidate.clear();
                stable_polls = 0;
                continue;
            }
            if candidate == after_fingerprint {
                stable_polls = stable_polls.saturating_add(1);
            } else {
                candidate = after_fingerprint;
                stable_polls = 1;
            }
            if stable_polls < PROFILE_STABLE_POLLS {
                continue;
            }
            match record_external_change(&paths.dsh_home, &before, &after, "restart-required") {
                Ok(Some(pending)) => {
                    println!("[dsh] detected plugin profile change from an external dsh command");
                    emit_bridge_event(&handle, "plugin-change-detected", pending);
                }
                Ok(None) => {}
                Err(error) => eprintln!("[dsh] failed to record external plugin change: {error}"),
            }
            candidate.clear();
            stable_polls = 0;
        }
    });
}

#[cfg(unix)]
fn signal_process_group(child: &Child, signal: i32) {
    let pid = child.id() as i32;
    let result = unsafe { libc::kill(-pid, signal) };
    if result != 0 {
        unsafe {
            libc::kill(pid, signal);
        }
    }
}

fn terminate_child(child: &mut Child) {
    if child.try_wait().ok().flatten().is_some() {
        return;
    }

    #[cfg(unix)]
    signal_process_group(child, libc::SIGTERM);
    #[cfg(not(unix))]
    let _ = child.kill();

    let deadline = std::time::Instant::now() + STOP_GRACE;
    while std::time::Instant::now() < deadline {
        if child.try_wait().ok().flatten().is_some() {
            return;
        }
        thread::sleep(Duration::from_millis(100));
    }

    #[cfg(unix)]
    signal_process_group(child, libc::SIGKILL);
    let _ = child.kill();
    let _ = child.wait();
}

fn kill_child() {
    if let Ok(mut guard) = CHILD.lock() {
        if let Some(mut child) = guard.take() {
            terminate_child(&mut child);
        }
    }
}

fn stop_managed_child() {
    CHILD_GENERATION.fetch_add(1, Ordering::SeqCst);
    kill_child();
}

#[derive(Clone, Copy)]
enum RecoveryAction {
    Retry,
    Restore,
    SafeMode,
}

fn perform_recovery_action(handle: tauri::AppHandle, action: RecoveryAction) -> Result<(), String> {
    let _operation = OperationGuard::acquire()?;
    let paths = harness_paths();
    set_recovery_state("restarting", "", matches!(action, RecoveryAction::SafeMode));
    stop_managed_child();

    if matches!(action, RecoveryAction::Restore) {
        let restore_result = restore_last_known_good(&paths.dsh_home)
            .and_then(|()| sync_profile_modules_after_restore(&paths.dsh_home));
        if let Err(error) = restore_result {
            set_recovery_state("failed", &error, false);
            let _ = show_recovery_window(&handle);
            return Err(error);
        }
        if let Err(error) = clear_pending_install(&paths.dsh_home) {
            eprintln!("[dsh] warning: {error}");
        }
    }

    let mode = if matches!(action, RecoveryAction::SafeMode) {
        Some(LaunchMode::Safe)
    } else {
        None
    };
    let result = if let Some(mode) = mode {
        start_harness(mode).and_then(|(child, url, tail)| {
            register_harness(&handle, child, mode, tail)?;
            if let Err(error) = show_harness_window(&handle, url, mode, None) {
                stop_managed_child();
                return Err(error);
            }
            Ok(())
        })
    } else {
        launch_normal_with_pending_fallback(&handle)
    };
    if let Err(error) = result {
        eprintln!("[dsh] recovery launch failed: {error}");
        set_recovery_state("failed", &error, mode == Some(LaunchMode::Safe));
        let _ = show_recovery_window(&handle);
        return Err(error);
    }
    Ok(())
}

async fn run_recovery_action(
    handle: tauri::AppHandle,
    action: RecoveryAction,
) -> Result<(), String> {
    tauri::async_runtime::spawn_blocking(move || perform_recovery_action(handle, action))
        .await
        .map_err(|error| format!("recovery task failed: {error}"))?
}

#[tauri::command]
fn recovery_status() -> serde_json::Value {
    let paths = harness_paths();
    let (phase, error, safe_mode) = RECOVERY_STATE
        .lock()
        .map(|state| (state.phase.clone(), state.error.clone(), state.safe_mode))
        .unwrap_or_else(|_| {
            (
                "failed".into(),
                "Harness recovery state is unavailable.".into(),
                false,
            )
        });
    serde_json::json!({
        "phase": phase,
        "error": error,
        "safeMode": safe_mode,
        "busy": OPERATION_ACTIVE.load(Ordering::SeqCst),
        "snapshotAvailable": snapshot_available_at(&paths.dsh_home),
        "detectedPlugin": detected_plugin(&error),
    })
}

#[tauri::command]
async fn retry_harness(handle: tauri::AppHandle) -> Result<(), String> {
    run_recovery_action(handle, RecoveryAction::Retry).await
}

#[tauri::command]
async fn restore_last_good(handle: tauri::AppHandle) -> Result<(), String> {
    run_recovery_action(handle, RecoveryAction::Restore).await
}

#[tauri::command]
async fn start_safe_mode(handle: tauri::AppHandle) -> Result<(), String> {
    run_recovery_action(handle, RecoveryAction::SafeMode).await
}

fn plugin_manager_status_value() -> Result<serde_json::Value, String> {
    let paths = harness_paths();
    let manifest = read_web_manifest(&paths.dsh_home)?;
    let pending = read_pending_install(&paths.dsh_home)?;
    let (phase, safe_mode) = RECOVERY_STATE
        .lock()
        .map(|state| (state.phase.clone(), state.safe_mode))
        .unwrap_or_else(|_| ("failed".into(), false));
    Ok(serde_json::json!({
        "installed": installed_plugins(&manifest),
        "pending": pending,
        "busy": OPERATION_ACTIVE.load(Ordering::SeqCst),
        "phase": phase,
        "safeMode": safe_mode,
        "installerReady": bundled_pnpm_path().is_file(),
    }))
}

fn perform_plugin_install(spec: String) -> Result<serde_json::Value, String> {
    let spec = validate_plugin_spec(&spec)?;
    let _operation = OperationGuard::acquire()?;
    let paths = harness_paths();
    if read_pending_install(&paths.dsh_home)?.is_some() {
        return Err("已有一个插件等待重启验证；请先重启或撤销，再安装下一个。".into());
    }
    let before = read_web_manifest(&paths.dsh_home)?;
    let before_state = plugin_profile_state(&before);
    let before_fingerprint = plugin_state_fingerprint(&before_state);
    write_profile_snapshot(&paths.dsh_home, BEFORE_PLUGIN_INSTALL)?;
    write_pending_change(
        &paths.dsh_home,
        PendingChange {
            source: "desktop",
            spec: Some(&spec),
            state: "installing",
            packages: &[],
            changes: &[],
            rollback_snapshot: BEFORE_PLUGIN_INSTALL,
            before_fingerprint: Some(&before_fingerprint),
            after_fingerprint: None,
        },
    )?;

    let install_result = run_plugin_add(&spec).and_then(|()| {
        let after = read_web_manifest(&paths.dsh_home)?;
        let after_state = plugin_profile_state(&after);
        let changes = plugin_state_changes(&before_state, &after_state);
        if changes.is_empty() {
            return Err("安装命令完成，但 web profile 没有出现可识别的插件变化。".into());
        }
        let packages = changed_plugin_names(&changes);
        let after_fingerprint = plugin_state_fingerprint(&after_state);
        write_pending_change(
            &paths.dsh_home,
            PendingChange {
                source: "desktop",
                spec: Some(&spec),
                state: "restart-required",
                packages: &packages,
                changes: &changes,
                rollback_snapshot: BEFORE_PLUGIN_INSTALL,
                before_fingerprint: Some(&before_fingerprint),
                after_fingerprint: Some(&after_fingerprint),
            },
        )
    });

    if let Err(error) = install_result {
        let rollback = rollback_pending_install(&paths.dsh_home);
        return Err(match rollback {
            Ok(_) => format!("{error}\n\n安装产生的 profile 改动已自动撤销。"),
            Err(rollback_error) => {
                format!("{error}\n\n安装失败后的自动撤销也未完成：{rollback_error}")
            }
        });
    }
    drop(_operation);
    plugin_manager_status_value()
}

fn perform_plugin_remove(name: String) -> Result<serde_json::Value, String> {
    let name = name.trim().to_string();
    if !valid_package_name(&name) {
        return Err("插件名称无效，无法移除。".into());
    }
    let _operation = OperationGuard::acquire()?;
    let paths = harness_paths();
    if read_pending_install(&paths.dsh_home)?.is_some() {
        return Err("已有一个插件变更等待重启验证；请先重启，再进行移除。".into());
    }
    let before = read_web_manifest(&paths.dsh_home)?;
    if before["dependencies"].get(&name).is_none() {
        return Err(format!("{name} 不属于当前 web profile 的用户插件。"));
    }
    let before_state = plugin_profile_state(&before);
    let before_fingerprint = plugin_state_fingerprint(&before_state);
    write_profile_snapshot(&paths.dsh_home, BEFORE_PLUGIN_INSTALL)?;
    write_pending_change(
        &paths.dsh_home,
        PendingChange {
            source: "desktop",
            spec: Some(&name),
            state: "installing",
            packages: &[],
            changes: &[],
            rollback_snapshot: BEFORE_PLUGIN_INSTALL,
            before_fingerprint: Some(&before_fingerprint),
            after_fingerprint: None,
        },
    )?;

    let remove_result = run_plugin_remove(&name).and_then(|()| {
        let after = read_web_manifest(&paths.dsh_home)?;
        let after_state = plugin_profile_state(&after);
        let changes = plugin_state_changes(&before_state, &after_state);
        if changes.is_empty() {
            return Err("移除命令完成，但 web profile 没有出现可识别的插件变化。".into());
        }
        let packages = changed_plugin_names(&changes);
        let after_fingerprint = plugin_state_fingerprint(&after_state);
        write_pending_change(
            &paths.dsh_home,
            PendingChange {
                source: "desktop",
                spec: Some(&name),
                state: "restart-required",
                packages: &packages,
                changes: &changes,
                rollback_snapshot: BEFORE_PLUGIN_INSTALL,
                before_fingerprint: Some(&before_fingerprint),
                after_fingerprint: Some(&after_fingerprint),
            },
        )
    });

    if let Err(error) = remove_result {
        let rollback = rollback_pending_install(&paths.dsh_home);
        return Err(match rollback {
            Ok(_) => format!("{error}\n\n移除产生的 profile 改动已自动撤销。"),
            Err(rollback_error) => {
                format!("{error}\n\n移除失败后的自动撤销也未完成：{rollback_error}")
            }
        });
    }
    drop(_operation);
    plugin_manager_status_value()
}

fn perform_plugin_restart(handle: tauri::AppHandle) -> Result<(), String> {
    let _operation = OperationGuard::acquire()?;
    let paths = harness_paths();
    if read_pending_install(&paths.dsh_home)?.is_none() {
        return Err("没有等待重启验证的插件。".into());
    }
    set_recovery_state("restarting", "", false);
    stop_managed_child();
    if let Err(error) = launch_normal_with_pending_fallback(&handle) {
        set_recovery_state("failed", &error, false);
        let _ = show_recovery_window(&handle);
        return Err(error);
    }
    Ok(())
}

#[cfg(unix)]
fn install_signal_handler(handle: tauri::AppHandle) -> Result<(), String> {
    use signal_hook::consts::signal::{SIGINT, SIGTERM};
    use signal_hook::iterator::Signals;

    let mut signals = Signals::new([SIGINT, SIGTERM])
        .map_err(|error| format!("failed to register signal handler: {error}"))?;
    thread::spawn(move || {
        if signals.forever().next().is_some() {
            handle.exit(0);
        }
    });
    Ok(())
}

#[cfg(not(unix))]
fn install_signal_handler(_handle: tauri::AppHandle) -> Result<(), String> {
    Ok(())
}

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.show();
                let _ = window.set_focus();
            }
        }))
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![
            recovery_status,
            retry_harness,
            restore_last_good,
            start_safe_mode
        ])
        .setup(|app| {
            install_signal_handler(app.handle().clone()).map_err(std::io::Error::other)?;
            let handle = app.handle().clone();
            if let Err(error) = launch_normal_with_pending_fallback(&handle) {
                stop_managed_child();
                eprintln!("[dsh] startup failed: {error}");
                set_recovery_state("failed", &error, false);
                show_recovery_window(&handle).map_err(std::io::Error::other)?;
            }
            start_profile_watcher(handle);
            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("failed to build tauri app")
        .run(|app_handle, event| match event {
            tauri::RunEvent::Exit => {
                println!("[dsh] exiting, stopping harness");
                stop_managed_child();
            }
            tauri::RunEvent::WindowEvent { label, event, .. } =>
            {
                #[cfg(target_os = "macos")]
                if label == "main" {
                    if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                        api.prevent_close();
                        if let Some(window) = app_handle.get_webview_window("main") {
                            let _ = window.hide();
                        }
                    }
                }
            }
            #[cfg(target_os = "macos")]
            tauri::RunEvent::Reopen { .. } => {
                if let Some(window) = app_handle.get_webview_window("main") {
                    let _ = window.show();
                    let _ = window.set_focus();
                }
            }
            _ => {}
        });
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::time::{SystemTime, UNIX_EPOCH};

    use super::{
        desktop_preferences_path, detected_plugin, ensure_desktop_settings_module_link,
        installed_plugins, parse_readiness, pending_change_outcome, plugin_profile_state,
        plugin_state_changes, plugin_state_fingerprint, read_desktop_preferences,
        redact_startup_line, resolve_modules_directory, restore_last_known_good,
        safe_profile_manifest, same_file, smooth_stream_enabled_from, usage_record_from_event,
        validate_plugin_spec, without_cli_path_block, write_profile_snapshot,
        write_smooth_stream_preference, CLI_PATH_BLOCK, LEGACY_CLI_PATH_BLOCK,
    };

    #[test]
    fn accepts_only_explicit_loopback_readiness_urls() {
        assert_eq!(
            parse_readiness("dsh web: http://127.0.0.1:3210").map(|url| url.as_str().to_string()),
            Some("http://127.0.0.1:3210/".into())
        );
        for line in [
            "prefix dsh web: http://127.0.0.1:3210",
            "dsh web: https://127.0.0.1:3210",
            "dsh web: http://127.0.0.1.evil.example:3210",
            "dsh web: http://localhost:3210",
            "dsh web: http://127.0.0.1",
            "dsh web: http://127.0.0.1:3210/?token=secret",
        ] {
            assert!(parse_readiness(line).is_none(), "accepted {line}");
        }
    }

    #[test]
    fn extracts_only_recent_committed_provider_usage_for_the_title_bar() {
        let event = serde_json::json!({
            "type": "assistant/message",
            "seq": 42,
            "time": 1_800_000,
            "data": {
                "message": {
                    "id": "message-1",
                    "role": "assistant",
                    "content": [],
                    "source": {
                        "kind": "model",
                        "provider": "deepseek-official",
                        "model": "deepseek-v4-flash"
                    }
                },
                "usage": {
                    "inputTokens": 100,
                    "outputTokens": 20,
                    "cacheReadTokens": 400
                }
            }
        });
        let record = usage_record_from_event(&event, 1_700_000).unwrap();
        assert_eq!(record["id"], "message-1");
        assert_eq!(record["provider"], "deepseek-official");
        assert_eq!(record["usage"]["cacheReadTokens"], 400);
        assert_eq!(record["usage"]["cacheWriteTokens"], 0);
        assert!(usage_record_from_event(&event, 1_900_000).is_none());
        assert!(usage_record_from_event(
            &serde_json::json!({ "type": "assistant/chunk", "time": 1_800_000 }),
            1_700_000
        )
        .is_none());
    }

    #[test]
    fn persists_the_default_on_smooth_stream_preference_outside_the_dsh_profile() {
        assert!(smooth_stream_enabled_from(&serde_json::json!({})));
        assert!(smooth_stream_enabled_from(
            &serde_json::json!({ "smoothStreamEnabled": true })
        ));
        assert!(!smooth_stream_enabled_from(
            &serde_json::json!({ "smoothStreamEnabled": false })
        ));

        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dsh_home = std::env::temp_dir().join(format!(
            "dsh-desktop-smooth-stream-test-{}-{unique}",
            std::process::id()
        ));
        let path = desktop_preferences_path(&dsh_home);
        write_smooth_stream_preference(&path, false).unwrap();
        let stored = read_desktop_preferences(&path).unwrap();
        assert!(!smooth_stream_enabled_from(&stored));
        assert!(!dsh_home.join("profiles/web").exists());
        fs::remove_dir_all(dsh_home).unwrap();
    }

    #[test]
    fn redacts_sensitive_startup_output() {
        assert_eq!(
            redact_startup_line("provider api_key=secret-value"),
            "[redacted sensitive startup detail]"
        );
        assert_eq!(
            redact_startup_line("failed to apply loader entry daily-review"),
            "failed to apply loader entry daily-review"
        );
    }

    #[test]
    fn finds_only_safe_package_names_in_loader_errors() {
        let error = "failed to apply loader entry row (@scope/first)\n\
            failed to apply loader entry daily (dsh-daily-review)";
        assert_eq!(detected_plugin(error).as_deref(), Some("dsh-daily-review"));
        assert_eq!(
            detected_plugin("failed to apply loader entry row (bad package)"),
            None
        );
    }

    #[test]
    fn accepts_public_plugin_specs_without_forwarding_pnpm_options() {
        for spec in [
            "dsh-daily-review",
            "@community/dsh-theme@1.2.0",
            "github:owner/repo#v1.0.0",
            "https://github.com/owner/repo.git#main",
            "git+https://github.com/owner/repo.git",
        ] {
            assert_eq!(validate_plugin_spec(spec).unwrap(), spec);
        }
        for spec in [
            "--global",
            "../local-plugin",
            "link:/tmp/plugin",
            "ssh://git@github.com/owner/repo",
            "https://example.com/plugin.tgz",
            "package name",
        ] {
            assert!(validate_plugin_spec(spec).is_err(), "accepted {spec}");
        }
    }

    #[test]
    fn extracts_plugin_spec_from_documented_install_command() {
        assert_eq!(
            validate_plugin_spec("dsh plugin --profile web add github:owner/example-plugin")
                .unwrap(),
            "github:owner/example-plugin"
        );
        assert_eq!(
            validate_plugin_spec("dsh.exe plugin --profile=web add github:owner/repo").unwrap(),
            "github:owner/repo"
        );

        for command in [
            "dsh plugin --profile tui add github:owner/repo",
            "dsh plugin --profile web remove dsh-plugin",
            "dsh plugin --profile web add github:owner/repo --global",
        ] {
            assert!(validate_plugin_spec(command).is_err(), "accepted {command}");
        }
    }

    #[test]
    fn lists_dependency_managed_plugins_and_bundle_state() {
        let manifest = serde_json::json!({
            "dependencies": {
                "plain-library": "1.0.0",
                "dsh-daily-review": "2.0.0"
            },
            "dsh": { "profile": { "bundles": [
                "@deepseek-ai/dsh-base",
                "dsh-daily-review"
            ] } }
        });
        let plugins = installed_plugins(&manifest);
        assert_eq!(plugins[0]["name"], "dsh-daily-review");
        assert_eq!(plugins[0]["active"], true);
        assert_eq!(plugins[1]["name"], "plain-library");
        assert_eq!(plugins[1]["active"], false);
    }

    #[test]
    fn detects_installed_updated_removed_and_activated_plugins() {
        let before = plugin_profile_state(&serde_json::json!({
            "dependencies": {
                "removed-plugin": "1.0.0",
                "updated-plugin": "1.0.0",
                "activated-plugin": "1.0.0"
            },
            "dsh": { "profile": { "bundles": ["removed-plugin", "updated-plugin"] } }
        }));
        let after = plugin_profile_state(&serde_json::json!({
            "dependencies": {
                "installed-plugin": "1.0.0",
                "updated-plugin": "2.0.0",
                "activated-plugin": "1.0.0"
            },
            "dsh": { "profile": { "bundles": [
                "installed-plugin", "updated-plugin", "activated-plugin"
            ] } }
        }));
        let changes = plugin_state_changes(&before, &after);
        let kinds: std::collections::BTreeMap<_, _> = changes
            .iter()
            .map(|change| {
                (
                    change["name"].as_str().unwrap(),
                    change["kind"].as_str().unwrap(),
                )
            })
            .collect();
        assert_eq!(kinds["installed-plugin"], "installed");
        assert_eq!(kinds["removed-plugin"], "removed");
        assert_eq!(kinds["updated-plugin"], "updated");
        assert_eq!(kinds["activated-plugin"], "activated");
        assert_ne!(
            plugin_state_fingerprint(&before),
            plugin_state_fingerprint(&after)
        );
    }

    #[test]
    fn reports_the_verified_plugin_operation_outcome() {
        for (kind, expected) in [
            ("installed", "enabled"),
            ("activated", "enabled"),
            ("removed", "removed"),
            ("updated", "updated"),
            ("deactivated", "disabled"),
        ] {
            let pending = serde_json::json!({ "changes": [{ "kind": kind }] });
            assert_eq!(pending_change_outcome(&pending), expected);
        }
        let mixed = serde_json::json!({
            "changes": [{ "kind": "installed" }, { "kind": "updated" }]
        });
        assert_eq!(pending_change_outcome(&mixed), "changed");
    }

    #[test]
    fn rewrites_the_managed_cli_path_block_without_duplicates() {
        let profile = format!(
            "export PATH=/custom/bin:$PATH\n\n{LEGACY_CLI_PATH_BLOCK}{CLI_PATH_BLOCK}alias dsh=legacy\n"
        );
        let cleaned = without_cli_path_block(&profile);
        assert_eq!(cleaned.matches("DeepSeek Harness Desktop CLI").count(), 0);
        assert_eq!(cleaned.matches("DSH Desktop CLI").count(), 0);
        assert!(cleaned.contains("export PATH=/custom/bin:$PATH"));
        assert!(cleaned.contains("alias dsh=legacy"));
    }

    #[test]
    fn safe_profile_keeps_built_in_bundles_and_skips_dependencies() {
        let source = serde_json::json!({
            "name": "dsh-profile-web",
            "dependencies": {
                "dsh-daily-review": "1.0.0",
                "@community/theme": "2.0.0"
            },
            "dsh": { "profile": { "bundles": [
                "@deepseek-ai/dsh-base",
                "@deepseek-ai/dsh-web-app",
                "dsh-daily-review",
                "@community/theme"
            ] } }
        });
        let safe = safe_profile_manifest(&source).unwrap();
        assert_eq!(safe["name"], "dsh-profile-desktop-safe");
        assert_eq!(
            safe["dsh"]["profile"]["bundles"],
            serde_json::json!(["@deepseek-ai/dsh-base", "@deepseek-ai/dsh-web-app"])
        );
    }

    #[test]
    fn snapshot_restore_changes_only_plugin_transaction_files() {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dsh_home = std::env::temp_dir().join(format!(
            "dsh-desktop-recovery-test-{}-{unique}",
            std::process::id()
        ));
        let profile = dsh_home.join("profiles/web");
        fs::create_dir_all(&profile).unwrap();
        fs::write(profile.join("package.json"), b"{\"version\":1}\n").unwrap();
        fs::write(profile.join("pnpm-lock.yaml"), b"lockfileVersion: '9.0'\n").unwrap();
        fs::write(profile.join("cordis.patch.yml"), b"- id: user-setting\n").unwrap();
        write_profile_snapshot(&dsh_home, "last-known-good").unwrap();

        fs::write(profile.join("package.json"), b"{\"version\":2}\n").unwrap();
        fs::write(profile.join("pnpm-workspace.yaml"), b"packages: []\n").unwrap();
        fs::write(profile.join("cordis.patch.yml"), b"- id: changed-setting\n").unwrap();
        restore_last_known_good(&dsh_home).unwrap();

        assert_eq!(
            fs::read_to_string(profile.join("package.json")).unwrap(),
            "{\"version\":1}\n"
        );
        assert!(!profile.join("pnpm-workspace.yaml").exists());
        assert_eq!(
            fs::read_to_string(profile.join("cordis.patch.yml")).unwrap(),
            "- id: changed-setting\n"
        );
        fs::remove_dir_all(dsh_home).unwrap();
    }

    #[test]
    fn links_desktop_settings_plugin_into_the_profile_module_fallback() {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dsh_home = std::env::temp_dir().join(format!(
            "dsh-desktop-settings-link-test-{}-{unique}",
            std::process::id()
        ));
        ensure_desktop_settings_module_link(&dsh_home).unwrap();
        let link = dsh_home
            .join("profiles/node_modules")
            .join("dsh-desktop-settings-plugin");
        let source = resolve_modules_directory().join("dsh-desktop-settings-plugin");
        assert!(same_file(&link, &source));
        ensure_desktop_settings_module_link(&dsh_home).unwrap();
        assert!(same_file(&link, &source));
        fs::remove_dir_all(dsh_home).unwrap();
    }
}
