use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};

#[cfg(unix)]
use std::os::unix::process::CommandExt;

fn executable_dir() -> Result<PathBuf, String> {
    let executable = env::current_exe()
        .map_err(|error| format!("dsh: failed to locate the desktop launcher: {error}"))?;
    fs::canonicalize(&executable)
        .unwrap_or(executable)
        .parent()
        .map(Path::to_path_buf)
        .ok_or_else(|| "dsh: desktop launcher has no parent directory".to_string())
}

fn modules_directory(executable_dir: &Path) -> Result<PathBuf, String> {
    let contents = executable_dir
        .parent()
        .ok_or_else(|| "dsh: invalid desktop application layout".to_string())?;
    for candidate in [
        contents.join("Resources/node_modules"),
        contents.join("Resources/_up_/node_modules"),
    ] {
        if candidate.join("@deepseek-ai/dsh/lib/bin.js").is_file() {
            return Ok(candidate);
        }
    }
    Err(
        "dsh: bundled DeepSeek Harness runtime is missing; reinstall the desktop application"
            .to_string(),
    )
}

fn run() -> Result<ExitCode, String> {
    let executable_dir = executable_dir()?;
    let node = executable_dir.join(if cfg!(windows) { "node.exe" } else { "node" });
    if !node.is_file() {
        return Err(
            "dsh: bundled Node.js runtime is missing; reinstall the desktop application"
                .to_string(),
        );
    }
    let modules = modules_directory(&executable_dir)?;
    let invoked_as = env::args_os()
        .next()
        .and_then(|path| PathBuf::from(path).file_stem().map(|name| name.to_owned()))
        .and_then(|name| name.to_str().map(str::to_string))
        .unwrap_or_else(|| "dsh".to_string());
    let is_pnpm = invoked_as == "pnpm";
    let script = if is_pnpm {
        modules.join("pnpm/bin/pnpm.mjs")
    } else {
        modules.join("@deepseek-ai/dsh/lib/bin.js")
    };
    let mut paths = vec![executable_dir, modules.join(".bin")];
    if let Some(existing) = env::var_os("PATH") {
        paths.extend(env::split_paths(&existing));
    }
    let path = env::join_paths(paths)
        .map_err(|error| format!("dsh: failed to construct runtime PATH: {error}"))?;

    let mut command = Command::new(node);
    if !is_pnpm {
        command.arg("--expose-internals");
    }
    command
        .arg(script)
        .args(env::args_os().skip(1))
        .env("PATH", path);

    #[cfg(unix)]
    {
        let error = command.exec();
        Err(format!(
            "dsh: failed to start bundled DeepSeek Harness: {error}"
        ))
    }

    #[cfg(not(unix))]
    {
        let status = command
            .status()
            .map_err(|error| format!("dsh: failed to start bundled DeepSeek Harness: {error}"))?;
        Ok(ExitCode::from(status.code().unwrap_or(1) as u8))
    }
}

fn main() -> ExitCode {
    match run() {
        Ok(code) => code,
        Err(error) => {
            eprintln!("{error}");
            ExitCode::FAILURE
        }
    }
}
