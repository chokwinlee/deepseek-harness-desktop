use std::env;
use std::io::Read;
#[cfg(unix)]
use std::os::unix::process::CommandExt;
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};

use qrcode::{render::svg, QrCode};

pub const REMOTE_PORT: u16 = 8443;
pub const LAN_REMOTE_PORT: u16 = 8765;
const SERVE_START_TIMEOUT: Duration = Duration::from_secs(12);
const SERVE_STOP_TIMEOUT: Duration = Duration::from_secs(4);

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct TailscaleInfo {
    pub executable: PathBuf,
    pub backend_state: String,
    pub node_id: String,
    pub dns_name: String,
    pub magic_dns: bool,
    pub https_ready: bool,
}

fn executable_name() -> &'static str {
    if cfg!(windows) {
        "tailscale.exe"
    } else {
        "tailscale"
    }
}

pub fn resolve_tailscale() -> Option<PathBuf> {
    if let Some(path) = env::var_os("DSH_TAILSCALE_PATH")
        .map(PathBuf::from)
        .filter(|path| path.is_file())
    {
        return Some(path);
    }
    if let Some(path) = env::var_os("PATH").and_then(|path| {
        env::split_paths(&path).find_map(|directory| {
            let candidate = directory.join(executable_name());
            candidate.is_file().then_some(candidate)
        })
    }) {
        return Some(path);
    }
    let candidates = if cfg!(windows) {
        vec![PathBuf::from(r"C:\Program Files\Tailscale\tailscale.exe")]
    } else {
        vec![
            PathBuf::from("/usr/local/bin/tailscale"),
            PathBuf::from("/opt/homebrew/bin/tailscale"),
            PathBuf::from("/Applications/Tailscale.app/Contents/MacOS/Tailscale"),
        ]
    };
    candidates.into_iter().find(|path| path.is_file())
}

fn run_json(executable: &PathBuf, arguments: &[&str]) -> Result<serde_json::Value, String> {
    let output = Command::new(executable)
        .args(arguments)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .map_err(|error| format!("无法启动 Tailscale：{error}"))?;
    if !output.status.success() {
        let detail = String::from_utf8_lossy(&output.stderr).trim().to_string();
        return Err(if detail.is_empty() {
            format!("Tailscale 命令失败（{}）。", output.status)
        } else {
            format!("Tailscale 命令失败：{detail}")
        });
    }
    serde_json::from_slice(&output.stdout)
        .map_err(|error| format!("Tailscale 返回了无法识别的状态：{error}"))
}

fn normalized_dns_name(value: &str) -> Option<String> {
    let value = value.trim().trim_end_matches('.').to_ascii_lowercase();
    let valid = !value.is_empty()
        && value.len() <= 253
        && value.ends_with(".ts.net")
        && value.split('.').all(|label| {
            !label.is_empty()
                && label.len() <= 63
                && !label.starts_with('-')
                && !label.ends_with('-')
                && label
                    .chars()
                    .all(|character| character.is_ascii_alphanumeric() || character == '-')
        });
    valid.then_some(value)
}

pub fn parse_tailscale_status(value: &serde_json::Value) -> Result<TailscaleInfo, String> {
    let executable = resolve_tailscale().unwrap_or_else(|| PathBuf::from(executable_name()));
    let backend_state = value["BackendState"].as_str().unwrap_or("").to_string();
    let node_id = value["Self"]["ID"]
        .as_str()
        .filter(|value| {
            value.starts_with('n')
                && value.len() <= 64
                && value
                    .chars()
                    .all(|character| character.is_ascii_alphanumeric())
        })
        .ok_or("Tailscale 没有返回有效的设备 ID。")?
        .to_string();
    let dns_name = value["Self"]["DNSName"]
        .as_str()
        .and_then(normalized_dns_name)
        .ok_or("Tailscale 没有返回有效的 .ts.net 设备域名。")?;
    let magic_dns = value["CurrentTailnet"]["MagicDNSEnabled"]
        .as_bool()
        .unwrap_or(false);
    let https_ready = value["CertDomains"]
        .as_array()
        .map(|domains| {
            domains.iter().any(|domain| {
                domain.as_str().and_then(normalized_dns_name).as_deref() == Some(dns_name.as_str())
            })
        })
        .unwrap_or(false);
    Ok(TailscaleInfo {
        executable,
        backend_state,
        node_id,
        dns_name,
        magic_dns,
        https_ready,
    })
}

pub fn inspect_tailscale() -> Result<TailscaleInfo, String> {
    let executable = resolve_tailscale()
        .ok_or("未找到 Tailscale。请先安装并登录，再重新打开 DeepSeek Harness Desktop。")?;
    let value = run_json(&executable, &["status", "--json"])?;
    let mut info = parse_tailscale_status(&value)?;
    info.executable = executable;
    if info.backend_state != "Running" {
        return Err(format!(
            "Tailscale 尚未连接（状态：{}）。",
            if info.backend_state.is_empty() {
                "Unknown"
            } else {
                &info.backend_state
            }
        ));
    }
    if !info.magic_dns {
        return Err("当前 Tailnet 尚未启用 MagicDNS。".into());
    }
    Ok(info)
}

pub fn serve_status(info: &TailscaleInfo) -> Result<serde_json::Value, String> {
    run_json(&info.executable, &["serve", "status", "--json"])
}

fn web_authority(info: &TailscaleInfo) -> String {
    format!("{}:{REMOTE_PORT}", info.dns_name)
}

fn proxy_from_handler(handler: &serde_json::Value) -> Option<&str> {
    handler
        .get("Proxy")
        .or_else(|| handler.get("proxy"))
        .and_then(serde_json::Value::as_str)
}

fn serve_configs(status: &serde_json::Value) -> Vec<&serde_json::Value> {
    let mut configs = vec![status];
    if let Some(foreground) = status
        .get("Foreground")
        .or_else(|| status.get("foreground"))
        .and_then(serde_json::Value::as_object)
    {
        configs.extend(foreground.values());
    }
    configs
}

fn configured_proxy_in_config<'a>(
    config: &'a serde_json::Value,
    info: &TailscaleInfo,
) -> Option<&'a str> {
    let web = config
        .get("Web")
        .or_else(|| config.get("web"))?
        .as_object()?;
    let server = web.get(&web_authority(info))?.as_object()?;
    let handlers = server
        .get("Handlers")
        .or_else(|| server.get("handlers"))?
        .as_object()?;
    let root = handlers.get("/")?;
    proxy_from_handler(root)
}

pub fn configured_proxy<'a>(
    status: &'a serde_json::Value,
    info: &TailscaleInfo,
) -> Option<&'a str> {
    serve_configs(status)
        .into_iter()
        .find_map(|config| configured_proxy_in_config(config, info))
}

fn remote_port_configured_in_config(config: &serde_json::Value, info: &TailscaleInfo) -> bool {
    let tcp_configured = config
        .get("TCP")
        .or_else(|| config.get("tcp"))
        .and_then(serde_json::Value::as_object)
        .is_some_and(|tcp| tcp.contains_key(&REMOTE_PORT.to_string()));
    let web_configured = config
        .get("Web")
        .or_else(|| config.get("web"))
        .and_then(serde_json::Value::as_object)
        .is_some_and(|web| web.contains_key(&web_authority(info)));
    tcp_configured || web_configured
}

pub fn remote_port_configured(status: &serde_json::Value, info: &TailscaleInfo) -> bool {
    serve_configs(status)
        .into_iter()
        .any(|config| remote_port_configured_in_config(config, info))
}

pub fn endpoint_url(info: &TailscaleInfo) -> String {
    format!("https://{}:{REMOTE_PORT}/", info.dns_name)
}

pub fn https_setup_url(info: &TailscaleInfo) -> Result<String, String> {
    let mut setup = tauri::Url::parse("https://login.tailscale.com/f/serve")
        .map_err(|error| format!("无法生成 Tailscale HTTPS 设置地址：{error}"))?;
    setup.query_pairs_mut().append_pair("node", &info.node_id);
    Ok(setup.to_string())
}

pub fn pairing_url(endpoint: &str) -> Result<String, String> {
    let mut pairing = tauri::Url::parse("harnessremote://connect")
        .map_err(|error| format!("无法生成配对地址：{error}"))?;
    pairing.query_pairs_mut().append_pair("url", endpoint);
    Ok(pairing.to_string())
}

pub fn authenticated_pairing_url(endpoint: &str, token: &str) -> Result<String, String> {
    if token.len() != 64 || !token.chars().all(|character| character.is_ascii_hexdigit()) {
        return Err("无法生成局域网配对地址：访问凭据无效。".into());
    }
    let mut pairing = tauri::Url::parse("harnessremote://connect")
        .map_err(|error| format!("无法生成局域网配对地址：{error}"))?;
    pairing
        .query_pairs_mut()
        .append_pair("url", endpoint)
        .append_pair("token", token)
        .append_pair("transport", "lan");
    Ok(pairing.to_string())
}

fn percent_encode_data_uri(value: &str) -> String {
    let mut encoded = String::with_capacity(value.len() * 2);
    for byte in value.bytes() {
        if byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.' | b'~') {
            encoded.push(byte as char);
        } else {
            encoded.push('%');
            encoded.push_str(&format!("{byte:02X}"));
        }
    }
    encoded
}

pub fn pairing_qr_data_uri(pairing: &str) -> Result<String, String> {
    let code =
        QrCode::new(pairing.as_bytes()).map_err(|error| format!("无法生成配对二维码：{error}"))?;
    let svg = code
        .render::<svg::Color>()
        .min_dimensions(288, 288)
        .quiet_zone(true)
        .build();
    Ok(format!(
        "data:image/svg+xml;charset=utf-8,{}",
        percent_encode_data_uri(&svg)
    ))
}

fn serve_flag() -> String {
    format!("--https={REMOTE_PORT}")
}

pub fn spawn_serve(info: &TailscaleInfo, target: &str) -> Result<Child, String> {
    let mut command = Command::new(&info.executable);
    command
        .arg("serve")
        .arg("--yes")
        .arg(serve_flag())
        .arg(target)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    #[cfg(unix)]
    command.process_group(0);
    command
        .spawn()
        .map_err(|error| format!("无法启动 Tailscale Serve：{error}"))
}

fn child_output(child: &mut Child) -> String {
    let mut values = Vec::new();
    if let Some(mut stream) = child.stderr.take() {
        let mut value = String::new();
        if stream.read_to_string(&mut value).is_ok() && !value.trim().is_empty() {
            values.push(value.trim().to_string());
        }
    }
    if let Some(mut stream) = child.stdout.take() {
        let mut value = String::new();
        if stream.read_to_string(&mut value).is_ok() && !value.trim().is_empty() {
            values.push(value.trim().to_string());
        }
    }
    values.join("\n").chars().take(4_000).collect()
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

pub fn terminate_serve(child: &mut Child) {
    if child.try_wait().ok().flatten().is_some() {
        return;
    }
    #[cfg(unix)]
    signal_process_group(child, libc::SIGTERM);
    #[cfg(not(unix))]
    let _ = child.kill();

    let deadline = Instant::now() + SERVE_STOP_TIMEOUT;
    while Instant::now() < deadline {
        if child.try_wait().ok().flatten().is_some() {
            return;
        }
        thread::sleep(Duration::from_millis(80));
    }
    #[cfg(unix)]
    signal_process_group(child, libc::SIGKILL);
    let _ = child.kill();
    let _ = child.wait();
}

pub fn wait_until_serving(
    child: &mut Child,
    info: &TailscaleInfo,
    expected_target: &str,
) -> Result<(), String> {
    let deadline = Instant::now() + SERVE_START_TIMEOUT;
    while Instant::now() < deadline {
        if let Some(status) = child
            .try_wait()
            .map_err(|error| format!("无法检查 Tailscale Serve：{error}"))?
        {
            let detail = child_output(child);
            return Err(if detail.is_empty() {
                format!("Tailscale Serve 提前退出（{status}）。")
            } else {
                format!("Tailscale Serve 提前退出：{detail}")
            });
        }
        if serve_status(info)
            .ok()
            .and_then(|status| configured_proxy(&status, info).map(str::to_string))
            .as_deref()
            == Some(expected_target)
        {
            return Ok(());
        }
        thread::sleep(Duration::from_millis(250));
    }
    terminate_serve(child);
    let detail = child_output(child);
    Err(if detail.is_empty() {
        "等待 Tailscale Serve 启动超时。".into()
    } else {
        format!("等待 Tailscale Serve 启动超时：{detail}")
    })
}

pub fn wait_until_port_clear(info: &TailscaleInfo) -> Result<(), String> {
    let deadline = Instant::now() + SERVE_STOP_TIMEOUT;
    while Instant::now() < deadline {
        match serve_status(info) {
            Ok(status) if !remote_port_configured(&status, info) => return Ok(()),
            Ok(_) => thread::sleep(Duration::from_millis(100)),
            Err(error) => return Err(error),
        }
    }
    Err(format!("Tailscale Serve 端口 {REMOTE_PORT} 未能及时释放。"))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn info() -> TailscaleInfo {
        TailscaleInfo {
            executable: PathBuf::from("tailscale"),
            backend_state: "Running".into(),
            node_id: "nExampleNode".into(),
            dns_name: "dsh-mac.example.ts.net".into(),
            magic_dns: true,
            https_ready: true,
        }
    }

    #[test]
    fn accepts_only_running_magic_dns_ts_net_nodes() {
        let value = serde_json::json!({
            "BackendState": "Running",
            "Self": { "ID": "nExampleNode", "DNSName": "dsh-mac.example.ts.net." },
            "CurrentTailnet": { "MagicDNSEnabled": true },
            "CertDomains": ["dsh-mac.example.ts.net"]
        });
        let parsed = parse_tailscale_status(&value).unwrap();
        assert_eq!(parsed.dns_name, "dsh-mac.example.ts.net");
        assert!(parsed.magic_dns);
        assert!(parsed.https_ready);

        let invalid = serde_json::json!({
            "BackendState": "Running",
            "Self": { "ID": "nExampleNode", "DNSName": "dsh-mac.example.com" },
            "CurrentTailnet": { "MagicDNSEnabled": true }
        });
        assert!(parse_tailscale_status(&invalid).is_err());
    }

    #[test]
    fn reads_only_the_exact_remote_serve_authority_and_target() {
        let status = serde_json::json!({
            "TCP": { "8443": { "HTTPS": true } },
            "Web": {
                "dsh-mac.example.ts.net:8443": {
                    "Handlers": { "/": { "Proxy": "http://127.0.0.1:3210" } }
                }
            }
        });
        assert!(remote_port_configured(&status, &info()));
        assert_eq!(
            configured_proxy(&status, &info()),
            Some("http://127.0.0.1:3210")
        );
        assert!(!remote_port_configured(&serde_json::json!({}), &info()));

        let foreground = serde_json::json!({
            "Foreground": {
                "d1079787276120ff": status
            }
        });
        assert!(remote_port_configured(&foreground, &info()));
        assert_eq!(
            configured_proxy(&foreground, &info()),
            Some("http://127.0.0.1:3210")
        );
    }

    #[test]
    fn pairing_payload_contains_the_remote_endpoint() {
        let endpoint = endpoint_url(&info());
        assert_eq!(endpoint, "https://dsh-mac.example.ts.net:8443/");
        let pairing = pairing_url(&endpoint).unwrap();
        assert_eq!(
            pairing,
            "harnessremote://connect?url=https%3A%2F%2Fdsh-mac.example.ts.net%3A8443%2F"
        );
        assert!(pairing_qr_data_uri(&pairing)
            .unwrap()
            .starts_with("data:image/svg+xml;charset=utf-8,"));
        assert_eq!(
            https_setup_url(&info()).unwrap(),
            "https://login.tailscale.com/f/serve?node=nExampleNode"
        );
        let lan_pairing = authenticated_pairing_url(
            "http://192.168.1.20:8765/",
            "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
        )
        .unwrap();
        assert!(lan_pairing
            .starts_with("harnessremote://connect?url=http%3A%2F%2F192.168.1.20%3A8765%2F&token="));
        assert!(lan_pairing.ends_with("&transport=lan"));
    }
}
