//! 从登录 shell 取回 PATH。
//!
//! GUI 应用由 launchd 拉起，PATH 只有 `/usr/bin:/bin:/usr/sbin:/sbin` 那一档，
//! 装在用户目录下的 nvm、pnpm 一概不在里面。从终端启动时进程继承了终端的 PATH，
//! 所以同一份代码从终端运行一切正常，打包成 .app 双击启动，服务就报
//! `sh: pnpm: command not found`。
//!
//! 这里在进程启动时跑一次登录 shell，把它的 PATH 取回来写进本进程，之后
//! spawn 的服务子进程自动继承。必须带 `-i`：zsh 只有交互时才读 `~/.zshrc`，
//! 而 `PNPM_HOME`、nvm 这些通常就配在那里，只给 `-lc` 是读不到的。

use std::ffi::CStr;
use std::process::{Command, Stdio};

/// 把 PATH 从 shell 的其它输出里框出来。交互式 shell 会加载提示符一类的插件，
/// 它们可能往 stdout 写东西，不能拿整个输出当结果。
const MARK: &str = "__HESTIA_PATH__";

/// 取回登录 shell 的 PATH 并写入本进程。
///
/// 必须在起任何线程之前调用：`set_var` 在多线程环境下不安全。
pub fn bootstrap() {
    let shell = login_shell();
    match probe(&shell) {
        Some(path) => std::env::set_var("PATH", path),
        // 取不到就沿用 launchd 给的 PATH。服务照旧会报 command not found，
        // 但应用本身能起来，还可以在服务配置的 env 里手动补 PATH
        None => eprintln!("[shellenv] 未能从 {shell} 取回 PATH，沿用当前环境"),
    }
}

fn probe(shell: &str) -> Option<String> {
    let out = Command::new(shell)
        .arg("-ilc")
        .arg(format!("printf '{MARK}%s{MARK}' \"$PATH\""))
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output()
        .ok()?;
    let text = String::from_utf8_lossy(&out.stdout);
    let path = text.split(MARK).nth(1)?.trim().to_string();
    if path.is_empty() {
        return None;
    }
    Some(path)
}

/// GUI 进程的环境里没有 `SHELL`，退回用户记录里的登录 shell
fn login_shell() -> String {
    if let Ok(s) = std::env::var("SHELL") {
        if !s.trim().is_empty() {
            return s;
        }
    }
    unsafe {
        let pw = libc::getpwuid(libc::getuid());
        if !pw.is_null() && !(*pw).pw_shell.is_null() {
            if let Ok(s) = CStr::from_ptr((*pw).pw_shell).to_str() {
                if !s.is_empty() {
                    return s.to_string();
                }
            }
        }
    }
    "/bin/sh".into()
}
