#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::env;
use std::io::{BufRead, BufReader};
#[cfg(unix)]
use std::os::unix::process::CommandExt;
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::sync::mpsc;
use std::sync::Mutex;
use std::thread;
use std::time::Duration;

use tauri::{Manager, WebviewUrl, WebviewWindowBuilder};
use tauri_plugin_opener::OpenerExt;

const READINESS_MARK: &str = "dsh web:";
const STARTUP_TIMEOUT: Duration = Duration::from_secs(120);
const READINESS_GRACE: Duration = Duration::from_millis(300);
const STOP_GRACE: Duration = Duration::from_secs(5);

static CHILD: Mutex<Option<Child>> = Mutex::new(None);

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

fn spawn_harness() -> Result<Child, String> {
    let node = resolve_node();
    let script = resolve_script();
    let home = env::var("SPIKE_HOME").unwrap_or_else(|_| env::var("HOME").unwrap_or_default());
    let dsh_home = env::var("SPIKE_HOME")
        .map(|value| format!("{value}/.dsh"))
        .unwrap_or_else(|_| env::var("DSH_HOME").unwrap_or_else(|_| format!("{home}/.dsh")));

    // The harness is spawned with `current_dir(home)`, and macOS refuses to
    // start a child whose working directory does not exist (ENOENT). That used
    // to surface as a setup error -> tauri panic -> abort() (panic = "abort"
    // in the release profile), so create the directory (and any missing
    // parents) up front so a missing SPIKE_HOME/HOME cannot abort startup.
    std::fs::create_dir_all(&home)
        .map_err(|error| format!("failed to create harness home directory {home}: {error}"))?;

    println!(
        "[dsh] node={} script={} home={}",
        node.display(),
        script.display(),
        home
    );
    let mut command = Command::new(&node);
    command
        .args([
            "--expose-internals",
            &script.to_string_lossy(),
            "web",
            "--host",
            "127.0.0.1",
            "--port",
            "0",
        ])
        .env("HOME", &home)
        .env("DSH_HOME", &dsh_home)
        .current_dir(&home)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
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

fn wait_readiness(child: &mut Child) -> Result<tauri::Url, String> {
    let stdout = child.stdout.take().ok_or("no stdout pipe")?;
    let stderr = child.stderr.take().ok_or("no stderr pipe")?;
    let (sender, receiver) = mpsc::channel::<Result<tauri::Url, String>>();

    thread::spawn(move || {
        let reader = BufReader::new(stderr);
        for line in reader.lines() {
            match line {
                Ok(value) => eprintln!("[dsh:err] {value}"),
                Err(_) => break,
            }
        }
    });

    thread::spawn(move || {
        let mut sent = false;
        let reader = BufReader::new(stdout);
        for line in reader.lines() {
            let line = match line {
                Ok(value) => value,
                Err(_) => break,
            };
            println!("[dsh:out] {line}");
            if !sent {
                if let Some(url) = parse_readiness(&line) {
                    let _ = sender.send(Ok(url));
                    sent = true;
                }
            }
        }
        if !sent {
            let _ = sender.send(Err("dsh stdout closed before readiness".into()));
        }
    });

    let url = receiver
        .recv_timeout(STARTUP_TIMEOUT)
        .map_err(|error| format!("timed out waiting for dsh readiness: {error}"))??;
    thread::sleep(READINESS_GRACE);
    if let Some(status) = child
        .try_wait()
        .map_err(|error| format!("failed to inspect dsh after readiness: {error}"))?
    {
        return Err(format!("dsh exited immediately after readiness: {status}"));
    }
    Ok(url)
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
        .setup(|app| {
            install_signal_handler(app.handle().clone()).map_err(std::io::Error::other)?;
            let handle = app.handle().clone();

            let mut child = spawn_harness().map_err(std::io::Error::other)?;
            println!("[dsh] harness spawned (pid {})", child.id());

            let url = match wait_readiness(&mut child) {
                Ok(value) => value,
                Err(error) => {
                    terminate_child(&mut child);
                    return Err(std::io::Error::other(error).into());
                }
            };
            println!("[dsh] harness ready at {url}");
            match acknowledge_onboarding(&url) {
                Ok(()) => println!("[dsh] upstream welcome notice acknowledged"),
                Err(error) => eprintln!("[dsh] warning: {error}"),
            }
            let harness_origin = url.origin().ascii_serialization();

            *CHILD
                .lock()
                .map_err(|_| std::io::Error::other("harness supervisor lock poisoned"))? =
                Some(child);
            println!("[dsh] harness registered under supervisor");

            let navigation_handle = handle.clone();
            let window = WebviewWindowBuilder::new(&handle, "main", WebviewUrl::External(url))
                .title("DeepSeek Harness Desktop")
                .inner_size(1440.0, 900.0)
                .min_inner_size(960.0, 640.0)
                .on_navigation(move |destination| {
                    if destination.origin().ascii_serialization() == harness_origin {
                        return true;
                    }
                    if matches!(destination.scheme(), "http" | "https" | "mailto") {
                        println!("[dsh] external navigation: {destination}");
                        let _ = navigation_handle
                            .opener()
                            .open_url(destination.as_str(), None::<&str>);
                    }
                    false
                })
                .build();
            if let Err(error) = window {
                kill_child();
                return Err(error.into());
            }
            println!("[dsh] window created");
            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("failed to build tauri app")
        .run(|app_handle, event| match event {
            tauri::RunEvent::Exit => {
                println!("[dsh] exiting, stopping harness");
                kill_child();
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
    use super::parse_readiness;

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
}
