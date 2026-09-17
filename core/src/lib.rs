//! Hestia 进程托管核心的 C ABI 外壳。
//!
//! 界面层通过 `hestia_call(方法名, JSON 参数)` 调用，返回 JSON 字符串；
//! 核心侧的主动通知（日志批次、服务状态变化、工作流进度）走 `hestia_init` 注册的回调。
//! 回调来自后台线程，界面层需自行切回主线程。

pub mod manager;
mod reaper;
mod shellenv;
pub mod types;

use std::ffi::{c_char, CStr, CString};
use std::path::PathBuf;
use std::sync::{Arc, Mutex, OnceLock};

use manager::Manager;
use types::*;

/// (事件名, JSON 负载)。两个指针仅在回调期间有效，需立即复制
pub type EventCb = extern "C" fn(*const c_char, *const c_char);

static MGR: OnceLock<Arc<Manager>> = OnceLock::new();
static CB: Mutex<Option<EventCb>> = Mutex::new(None);

fn cstr(s: &str) -> *mut c_char {
    CString::new(s).unwrap_or_default().into_raw()
}

fn read(p: *const c_char) -> String {
    if p.is_null() {
        return String::new();
    }
    unsafe { CStr::from_ptr(p) }.to_string_lossy().into_owned()
}

/// 取回登录 shell 的 PATH 写入本进程。必须在起任何线程之前调用
#[no_mangle]
pub extern "C" fn hestia_bootstrap() {
    shellenv::bootstrap();
}

/// 初始化核心。重复调用会被忽略
#[no_mangle]
pub extern "C" fn hestia_init(config_dir: *const c_char, cb: EventCb) {
    if MGR.get().is_some() {
        return;
    }
    *CB.lock().unwrap() = Some(cb);
    reaper::install();

    let dir = PathBuf::from(read(config_dir));
    let emit: manager::Emit = Arc::new(|name: &str, payload: String| {
        let Some(f) = *CB.lock().unwrap() else { return };
        let (Ok(n), Ok(p)) = (CString::new(name), CString::new(payload)) else {
            return;
        };
        f(n.as_ptr(), p.as_ptr());
    });
    let _ = MGR.set(Manager::new_in(dir, emit));
}

/// 调用一个方法。返回值是 JSON，调用方负责用 `hestia_free` 释放
#[no_mangle]
pub extern "C" fn hestia_call(method: *const c_char, args: *const c_char) -> *mut c_char {
    let Some(m) = MGR.get() else {
        return cstr("null");
    };
    let method = read(method);
    let args: serde_json::Value =
        serde_json::from_str(&read(args)).unwrap_or(serde_json::Value::Null);
    let id = || args["id"].as_str().unwrap_or_default().to_string();

    let out = match method.as_str() {
        "get_config" => serde_json::to_string(&m.config()).unwrap_or_default(),
        "snapshot" => serde_json::to_string(&m.snapshot()).unwrap_or_default(),
        "get_logs" => serde_json::to_string(&m.logs()).unwrap_or_default(),
        "save_service" => {
            if let Ok(svc) = serde_json::from_value::<ServiceConfig>(args) {
                m.save_service(svc);
            }
            "null".into()
        }
        "delete_service" => {
            m.delete_service(id());
            "null".into()
        }
        "reorder_services" => {
            if let Ok(ids) = serde_json::from_value::<Vec<String>>(args["ids"].clone()) {
                m.reorder_services(ids);
            }
            "null".into()
        }
        "set_prefs" => {
            if let Ok(p) = serde_json::from_value::<Prefs>(args) {
                m.set_prefs(p);
            }
            "null".into()
        }
        "start_service" => {
            m.start_as(&id(), args["profile"].as_str());
            "null".into()
        }
        "save_workflow" => {
            if let Ok(wf) = serde_json::from_value::<Workflow>(args) {
                m.save_workflow(wf);
            }
            "null".into()
        }
        "delete_workflow" => {
            m.delete_workflow(&id());
            "null".into()
        }
        "start_workflow" => {
            m.start_workflow(&id());
            "null".into()
        }
        "stop_workflow" => {
            m.stop_workflow(&id());
            "null".into()
        }
        "stop_service" => {
            m.stop(&id());
            "null".into()
        }
        "restart_service" => {
            m.restart(&id());
            "null".into()
        }
        "start_all" => {
            m.start_all();
            "null".into()
        }
        "stop_all" => {
            m.stop_all();
            "null".into()
        }
        "clear_logs" => {
            m.clear_logs();
            "null".into()
        }
        "kill_all_now" => {
            m.kill_all_now();
            "null".into()
        }
        other => format!("{{\"error\":\"未知方法 {other}\"}}"),
    };
    cstr(&out)
}

#[no_mangle]
pub extern "C" fn hestia_free(p: *mut c_char) {
    if !p.is_null() {
        unsafe { drop(CString::from_raw(p)) };
    }
}
