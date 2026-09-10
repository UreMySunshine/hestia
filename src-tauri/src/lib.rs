mod dismiss;
pub mod manager;
mod reaper;
mod shellenv;
mod tray;
pub mod types;

use std::sync::Arc;

use tauri::{AppHandle, Emitter, Manager as _, State, WindowEvent};

use manager::Manager;
use types::*;

type Mgr<'a> = State<'a, Arc<Manager>>;

#[tauri::command]
fn get_config(m: Mgr) -> AppConfig {
    m.config()
}

#[tauri::command]
fn save_service(m: Mgr, svc: ServiceConfig) {
    m.save_service(svc);
}

#[tauri::command]
fn reorder_services(m: Mgr, ids: Vec<String>) {
    m.reorder_services(ids);
}

#[tauri::command]
fn delete_service(m: Mgr, id: String) {
    m.delete_service(id);
}



#[tauri::command]
fn set_prefs(m: Mgr, prefs: Prefs) {
    m.set_prefs(prefs);
}

#[tauri::command]
fn start_service(m: Mgr, id: String) {
    m.start(&id);
}

#[tauri::command]
fn stop_service(m: Mgr, id: String) {
    m.stop(&id);
}

#[tauri::command]
fn restart_service(m: Mgr, id: String) {
    m.restart(&id);
}

#[tauri::command]
fn start_all(m: Mgr) {
    m.start_all();
}

#[tauri::command]
fn stop_all(m: Mgr) {
    m.stop_all();
}



#[tauri::command]
fn snapshot(m: Mgr) -> Snapshot {
    m.snapshot()
}

#[tauri::command]
fn get_logs(m: Mgr) -> Vec<LogLine> {
    m.logs()
}

#[tauri::command]
fn clear_logs(m: Mgr) {
    m.clear_logs();
}


#[tauri::command]
fn show_main(app: AppHandle) {
    if let Some(w) = app.get_webview_window("main") {
        let _ = w.unminimize();
        let _ = w.show();
        let _ = w.set_focus();
    }
    tray::hide_menubar(&app);
}

#[tauri::command]
fn hide_menubar(app: AppHandle) {
    tray::hide_menubar(&app);
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    // PATH 要在起任何线程之前定好：set_var 在多线程环境下不安全
    shellenv::bootstrap();

    tauri::Builder::default()
        .plugin(tauri_plugin_positioner::init())
        .plugin(tauri_plugin_dialog::init())
        .setup(|app| {
            // 可捕获的终止信号先兜一层，SIGKILL 只能靠下次启动时回收
            reaper::install();
            let handle = app.handle().clone();
            let mgr = Manager::new(handle.clone());
            app.manage(mgr.clone());
            tray::setup(&handle, mgr)?;
            dismiss::install(&handle);
            Ok(())
        })
        .on_window_event(|window, event| {
            if let WindowEvent::CloseRequested { api, .. } = event {
                // 主窗口关闭只收进菜单栏，进程继续托管
                if window.label() == "main" {
                    api.prevent_close();
                    let _ = window.hide();
                }
            }
            // 前端据此暂停背景动画，窗口不在前台时不做无谓合成
            if window.label() == "main" {
                if let WindowEvent::Focused(f) = event {
                    let _ = window.emit("main-focus", *f);
                    // 全局鼠标监视器只捕获其它应用的点击，点自家主窗口不会触发，
                    // 所以主窗口拿到焦点时也要把菜单栏面板收起来
                    if *f {
                        dismiss::dismiss(window.app_handle());
                    }
                }
            }
            // 菜单栏面板失焦即收起
            if window.label() == "menubar" {
                if let WindowEvent::Focused(false) = event {
                    let _ = window.hide();
                }
            }
        })
        .invoke_handler(tauri::generate_handler![
            get_config,
            save_service,
            delete_service,
            reorder_services,
            set_prefs,
            start_service,
            stop_service,
            restart_service,
            start_all,
            stop_all,
            snapshot,
            get_logs,
            clear_logs,
            show_main,
            hide_menubar
        ])
        .build(tauri::generate_context!())
        .expect("error while running tauri application")
        .run(|app, event| match event {
            // 退出前回收所有被托管的进程，避免留下孤儿
            tauri::RunEvent::Exit => {
                if let Some(m) = app.try_state::<Arc<Manager>>() {
                    m.kill_all_now();
                }
            }
            // 点 Dock 图标时主窗口已被关进菜单栏，这里把它放回来
            #[cfg(target_os = "macos")]
            tauri::RunEvent::Reopen { .. } => {
                if let Some(w) = app.get_webview_window("main") {
                    let _ = w.unminimize();
                    let _ = w.show();
                    let _ = w.set_focus();
                }
            }
            _ => {}
        });
}
