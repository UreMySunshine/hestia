use std::sync::Arc;
use std::time::Duration;

use tauri::{
    image::Image,
    menu::{Menu, MenuItem, PredefinedMenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    AppHandle, Manager as _,
};
use tauri_plugin_positioner::{Position, WindowExt};

use crate::manager::Manager;

fn show_main(app: &AppHandle) {
    if let Some(w) = app.get_webview_window("main") {
        let _ = w.unminimize();
        let _ = w.show();
        let _ = w.set_focus();
    }
}

pub fn hide_menubar(app: &AppHandle) {
    if let Some(w) = app.get_webview_window("menubar") {
        let _ = w.hide();
    }
}

/// 左键点击托盘图标时，在图标正下方开合菜单栏面板
fn toggle_menubar(app: &AppHandle) {
    let Some(w) = app.get_webview_window("menubar") else {
        return;
    };
    if w.is_visible().unwrap_or(false) {
        let _ = w.hide();
        return;
    }
    let _ = w.as_ref().window().move_window(Position::TrayBottomCenter);
    let _ = w.show();
    let _ = w.set_focus();
}

pub fn setup(app: &AppHandle, mgr: Arc<Manager>) -> tauri::Result<()> {
    let open = MenuItem::with_id(app, "open", "显示主窗口", true, None::<&str>)?;
    let start = MenuItem::with_id(app, "start", "全部启动", true, None::<&str>)?;
    let stop = MenuItem::with_id(app, "stop", "全部停止", true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "退出 Hestia", true, None::<&str>)?;
    let menu = Menu::with_items(
        app,
        &[
            &open,
            &PredefinedMenuItem::separator(app)?,
            &start,
            &stop,
            &PredefinedMenuItem::separator(app)?,
            &quit,
        ],
    )?;

    let idle = Image::from_bytes(include_bytes!("../icons/tray-idle.png"))?;
    let handler = mgr.clone();

    TrayIconBuilder::with_id("hestia")
        .icon(idle.clone())
        // 彩色图不能走 template 模式：那只取 alpha 渲染成单色剪影，颜色会全部丢失
        .icon_as_template(false)
        .tooltip("Hestia")
        .menu(&menu)
        .show_menu_on_left_click(false)
        .on_menu_event(move |app, event| match event.id().as_ref() {
            "open" => show_main(app),
            "start" => handler.start_all(),
            "stop" => handler.stop_all(),
            "quit" => app.exit(0),
            _ => {}
        })
        .on_tray_icon_event(|tray, event| {
            let app = tray.app_handle();
            // 位置信息交给 positioner 记录，TrayBottomCenter 才有依据
            tauri_plugin_positioner::on_tray_event(app, &event);
            // 悬停、按下、抬起都算托盘交互，全局监视器在此期间不收起面板
            crate::dismiss::mark_tray_activity();
            if let TrayIconEvent::Click {
                button: MouseButton::Left,
                button_state: MouseButtonState::Up,
                ..
            } = event
            {
                toggle_menubar(app);
            }
        })
        .build(app)?;

    animate(app.clone(), mgr, idle)?;
    Ok(())
}

/// 有服务在运行时循环播放尾焰各帧，全部停止时换回熄火的静止帧。
/// 帧只在启动时解码一次；图标没变化就不下发，避免无谓的重绘。
fn animate(app: AppHandle, mgr: Arc<Manager>, idle: Image<'static>) -> tauri::Result<()> {
    let frames = [
        Image::from_bytes(include_bytes!("../icons/tray-run-1.png"))?,
        Image::from_bytes(include_bytes!("../icons/tray-run-2.png"))?,
        Image::from_bytes(include_bytes!("../icons/tray-run-3.png"))?,
        Image::from_bytes(include_bytes!("../icons/tray-run-4.png"))?,
        Image::from_bytes(include_bytes!("../icons/tray-run-5.png"))?,
    ];

    std::thread::spawn(move || {
        let mut step = 0usize;
        let mut idling = true;
        loop {
            let Some(tray) = app.tray_by_id("hestia") else {
                return;
            };
            if mgr.any_running() {
                let _ = tray.set_icon(Some(frames[step % frames.len()].clone()));
                step += 1;
                idling = false;
                std::thread::sleep(Duration::from_millis(170));
            } else {
                if !idling {
                    let _ = tray.set_icon(Some(idle.clone()));
                    idling = true;
                }
                std::thread::sleep(Duration::from_millis(500));
            }
        }
    });
    Ok(())
}
