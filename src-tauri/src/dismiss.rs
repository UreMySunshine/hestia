//! 菜单栏面板的「点击别处即收起」。
//!
//! 原来靠 `WindowEvent::Focused(false)`，实测不成立：点状态栏图标展开面板时，
//! 日志里只有 `Moved`、`可见=true`，**从头到尾没有 `Focused(true)`**——
//! 面板从未成为 key window，自然也永远不会失焦。
//! 成因是点状态栏图标不会激活应用，而新版 macOS 限制后台应用的程序化激活，
//! `tao` 的 `set_focus` 里那句 `activateIgnoringOtherApps:` 不再生效。
//!
//! 这里改用 AppKit 的全局事件监视器：只要面板可见，别处发生鼠标按下就收起。
//! 鼠标事件的全局监视不需要辅助功能授权（只有键盘事件需要）。
//!
//! 注意监视器并非只捕获「其它应用」的事件——实测点托盘图标也会触发，
//! 处理办法见下面 QUIET 的说明。

use std::sync::Mutex;
use std::time::{Duration, Instant};

use block2::RcBlock;
use objc2_app_kit::{NSEvent, NSEventMask};
use tauri::{AppHandle, Manager};

/// 最近一次托盘图标事件的时刻
static LAST_TRAY_AT: Mutex<Option<Instant>> = Mutex::new(None);

/// 托盘交互的静默期。
///
/// 实测：点托盘图标产生的鼠标事件**也会**进全局监视器（状态栏的点击在新版 macOS 上
/// 由系统派发，对监视器而言算「其它应用」）。于是按下时监视器把面板关掉、抬起时
/// `toggle_menubar` 又开一次，双屏下两块屏幕的时序不同，就表现成「开了立刻关」。
///
/// 靠固定的「展开后豁免」挡不住，因为按下发生在展开之前。改成看托盘事件的时间：
/// 光标划过托盘图标时 tray-icon 会持续派发 Enter / Move，点击必然发生在这些事件之后，
/// 所以只要最近有托盘事件就跳过。光标移开后不再有事件，静默期自然失效，无需清理。
const QUIET: Duration = Duration::from_millis(400);

/// 由 tray.rs 在收到任何托盘图标事件时调用
pub fn mark_tray_activity() {
    *LAST_TRAY_AT.lock().unwrap() = Some(Instant::now());
}

/// 光标刚在托盘图标上活动过
pub fn near_tray() -> bool {
    LAST_TRAY_AT
        .lock()
        .unwrap()
        .map(|t| t.elapsed() < QUIET)
        .unwrap_or(false)
}

/// 收起菜单栏面板。托盘交互期间不动，避免和 toggle 打架
pub fn dismiss(app: &AppHandle) {
    if near_tray() {
        return;
    }
    if let Some(w) = app.get_webview_window("menubar") {
        if w.is_visible().unwrap_or(false) {
            let _ = w.hide();
        }
    }
}

pub fn install(app: &AppHandle) {
    let handle = app.clone();
    let block = RcBlock::new(move |_ev: core::ptr::NonNull<NSEvent>| {
        dismiss(&handle);
    });

    // 返回值是监视器句柄，用于日后 removeMonitor。这里要监听到进程结束，
    // 故意泄漏，不然句柄一析构监视器就失效了。
    let monitor = NSEvent::addGlobalMonitorForEventsMatchingMask_handler(
        NSEventMask::LeftMouseDown | NSEventMask::RightMouseDown,
        &block,
    );
    std::mem::forget(monitor);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tray_activity_opens_then_closes_the_quiet_window() {
        assert!(!near_tray(), "没有托盘事件时不应处于静默期");
        mark_tray_activity();
        assert!(near_tray(), "刚有托盘事件时应处于静默期");
        std::thread::sleep(QUIET + Duration::from_millis(80));
        assert!(!near_tray(), "超过 {QUIET:?} 后静默期应失效");
    }
}
