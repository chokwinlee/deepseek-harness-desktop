#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::env;
use std::io::{BufRead, BufReader};
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
    // exe_dir() already strips the filename (e.g. <App>.app/Contents/MacOS)
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
    if let Ok(p) = env::var("DSH_NODE") {
        return PathBuf::from(p);
    }
    let exe = exe_dir();
    let triple = target_triple();
    for name in [format!("node-{triple}"), "node".to_string()] {
        let cand = exe.join(name);
        if cand.exists() {
            return cand;
        }
    }
    PathBuf::from("node") // let spawn produce a clear error
}

/// dsh CLI entry in bundled resources; DSH_SCRIPT overrides.
fn resolve_script() -> PathBuf {
    if let Ok(p) = env::var("DSH_SCRIPT") {
        return PathBuf::from(p);
    }
    let rel = "node_modules/@deepseek-ai/dsh/lib/bin.js";
    for root in resource_roots() {
        let cand = root.join(rel);
        if cand.exists() {
            return cand;
        }
    }
    PathBuf::from(rel)
}

fn spawn_harness() -> Result<Child, String> {
    let node = resolve_node();
    let script = resolve_script();
    let home = env::var("SPIKE_HOME").unwrap_or_else(|_| env::var("HOME").unwrap_or_default());
    let dsh_home = env::var("SPIKE_HOME")
        .map(|h| format!("{h}/.dsh"))
        .unwrap_or_else(|_| env::var("DSH_HOME").unwrap_or_else(|_| format!("{home}/.dsh")));

    println!("[dsh] node={} script={} home={}", node.display(), script.display(), home);
    let mut cmd = Command::new(&node);
    cmd.args(["--expose-internals", &script.to_string_lossy(), "web", "--host", "127.0.0.1", "--port", "0"])
        .env("HOME", &home)
        .env("DSH_HOME", &dsh_home)
        .current_dir(&home)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    cmd.spawn()
        .map_err(|e| format!("failed to spawn {}: {e}", node.display()))
}

fn wait_readiness(child: &mut Child) -> Result<String, String> {
    let stdout = child.stdout.take().ok_or("no stdout pipe")?;
    let stderr = child.stderr.take().ok_or("no stderr pipe")?;
    let (tx, rx) = mpsc::channel::<Result<String, String>>();

    thread::spawn(move || {
        let reader = BufReader::new(stderr);
        for line in reader.lines() {
            match line {
                Ok(l) => println!("[dsh:err] {l}"),
                Err(_) => break,
            }
        }
    });

    thread::spawn(move || {
        let mut sent = false;
        let reader = BufReader::new(stdout);
        for line in reader.lines() {
            let line = match line {
                Ok(l) => l,
                Err(_) => break,
            };
            println!("[dsh:out] {line}");
            if !sent {
                if let Some(pos) = line.find(READINESS_MARK) {
                    let rest = line[pos + READINESS_MARK.len()..].trim();
                    if rest.starts_with("http://") {
                        let _ = tx.send(Ok(rest.to_string()));
                        sent = true;
                    }
                }
            }
        }
        if !sent {
            let _ = tx.send(Err("dsh stdout closed before readiness".into()));
        }
    });

    rx.recv_timeout(STARTUP_TIMEOUT)
        .map_err(|e| format!("timed out waiting for dsh readiness: {e}"))?
}

fn kill_child() {
    if let Some(mut child) = CHILD.lock().unwrap().take() {
        unsafe {
            libc::kill(child.id() as i32, libc::SIGTERM);
        }
        let deadline = std::time::Instant::now() + Duration::from_secs(2);
        loop {
            if child.try_wait().ok().flatten().is_some() {
                break;
            }
            if std::time::Instant::now() >= deadline {
                let _ = child.kill();
                let _ = child.wait();
                break;
            }
            thread::sleep(Duration::from_millis(100));
        }
    }
}

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
            if let Some(w) = app.get_webview_window("main") {
                let _ = w.show();
                let _ = w.set_focus();
            }
        }))
        .plugin(tauri_plugin_opener::init())
        .setup(|app| {
            let handle = app.handle().clone();

            let mut child = match spawn_harness() {
                Ok(c) => c,
                Err(e) => {
                    eprintln!("[dsh] {e}");
                    std::process::exit(1);
                }
            };
            println!("[dsh] harness spawned (pid {})", child.id());

            let url = match wait_readiness(&mut child) {
                Ok(u) => u,
                Err(e) => {
                    eprintln!("[dsh] {e}");
                    std::process::exit(1);
                }
            };
            println!("[dsh] harness ready at {url}");

            let parsed: tauri::Url = match url.parse() {
                Ok(u) => u,
                Err(e) => {
                    eprintln!("[dsh] invalid harness url: {e}");
                    std::process::exit(1);
                }
            };
            let harness_origin = parsed.origin().ascii_serialization();

            *CHILD.lock().unwrap() = Some(child);
            println!("[dsh] harness registered under supervisor");

            let nav_handle = handle.clone();
            WebviewWindowBuilder::new(&handle, "main", WebviewUrl::External(parsed))
                .title("DeepSeek Harness Desktop")
                .inner_size(1440.0, 900.0)
                .min_inner_size(960.0, 640.0)
                .on_navigation(move |url| {
                    let same = url.origin().ascii_serialization() == harness_origin;
                    if !same {
                        println!("[dsh] external navigation: {url}");
                        let _ = nav_handle.opener().open_url(url.as_str(), None::<&str>);
                    }
                    same
                })
                .build()?;
            println!("[dsh] window created");
            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("failed to build tauri app")
        .run(|_app_handle, event| {
            if let tauri::RunEvent::Exit = event {
                println!("[dsh] exiting, stopping harness");
                kill_child();
            }
        });
}