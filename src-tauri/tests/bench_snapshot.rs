//! 采样耗时的粗测，用来确认 snapshot 不会在 1.4 秒的节拍里占太多时间。
use std::time::Instant;

use hestia_lib::manager::Manager;
use hestia_lib::types::ServiceConfig;
use tauri::test::{mock_builder, mock_context, noop_assets};

#[test]
fn snapshot_is_cheap_enough_for_the_tick() {
    let dir = std::env::temp_dir().join(format!("hestia-bench-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("config.json"),
        r#"{"services":[],"prefs":{"autostart":false,"autorestart":true,"notify":false,"quiet":true}}"#).unwrap();
    let app = mock_builder().build(mock_context(noop_assets())).unwrap();
    let m = Manager::new_in(app.handle().clone(), dir.clone());

    // 空载：没有服务在跑
    m.snapshot();
    let t0 = Instant::now();
    for _ in 0..10 { m.snapshot(); }
    let idle = t0.elapsed().as_secs_f64() * 100.0;

    // 有进程在跑：需要遍历全系统进程建父子表，并探测监听端口。
    // 用一个真的会监听端口的命令，端口探到之后走缓存，测的才是稳态。
    m.save_service(ServiceConfig {
        id: "b1".into(), name: "b1".into(), proj: "bench".into(), ic: "chip".into(),
        cmd: "python3 -m http.server 19876 --bind 127.0.0.1".into(),
        stop: String::new(), cwd: String::new(),
        port: 19876, auto_restart: false, env: vec![],
    });
    m.start("b1");

    // 等到端口被探到；探到之后就不会再调 lsof，测的才是稳态
    let deadline = Instant::now() + std::time::Duration::from_secs(20);
    let mut detected = false;
    while Instant::now() < deadline {
        if m.snapshot().services.iter().any(|s| s.ports.contains(&19876)) {
            detected = true;
            break;
        }
        std::thread::sleep(std::time::Duration::from_millis(200));
    }
    assert!(detected, "应当能探测到实际监听的端口");

    let t1 = Instant::now();
    for _ in 0..10 { m.snapshot(); }
    let busy = t1.elapsed().as_secs_f64() * 100.0;
    m.stop("b1");

    println!("snapshot 单次耗时：空载 {idle:.1}ms / 有进程在跑且端口已探到 {busy:.1}ms（节拍 1400ms）");
    assert!(busy < 200.0, "单次采样 {busy:.1}ms 相对 1.4 秒节拍过重");

    let _ = std::fs::remove_dir_all(dir);
}
