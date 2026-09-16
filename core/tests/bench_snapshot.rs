//! 采样耗时的粗测，用来确认 snapshot 不会在 1.4 秒的节拍里占太多时间。
use std::time::Instant;

use hestia_core::manager::Manager;
use hestia_core::types::ServiceConfig;

#[test]
fn snapshot_is_cheap_enough_for_the_tick() {
    let dir = std::env::temp_dir().join(format!("hestia-bench-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("config.json"),
        r#"{"services":[],"prefs":{"autostart":false,"autorestart":true,"notify":false,"quiet":true}}"#).unwrap();
    let m = Manager::new_in(dir.clone(), std::sync::Arc::new(|_: &str, _: String| {}));

    // 空载：没有服务在跑
    m.snapshot();
    let t0 = Instant::now();
    for _ in 0..10 {
        m.snapshot();
    }
    let idle = t0.elapsed().as_secs_f64() * 100.0;

    // 有进程在跑：需要收集进程树、刷新其资源占用，并探测监听端口。
    // 用一个真的会监听端口的命令，端口探到之后走缓存，测的才是稳态。
    // 不用 http.server：它绑定端口后要先反查主机名才开始监听，CI 机器上这一步会卡住二十秒以上
    m.save_service(ServiceConfig {
        id: "b1".into(),
        name: "b1".into(),
        proj: "bench".into(),
        ic: "chip".into(),
        cmd: "python3 -c 'import socket, time; s = socket.socket(); s.bind((\"127.0.0.1\", 19876)); s.listen(); time.sleep(600)'".into(),
        stop: String::new(),
        cwd: String::new(),
        port: 19876,
        auto_restart: false,
        env: vec![],
    });
    m.start("b1");

    // 等到端口被探到；探到之后就不会再调 lsof，测的才是稳态
    let deadline = Instant::now() + std::time::Duration::from_secs(20);
    let mut detected = false;
    let mut last = None;
    while Instant::now() < deadline {
        let snap = m.snapshot();
        if snap.services.iter().any(|s| s.ports.contains(&19876)) {
            detected = true;
            break;
        }
        last = Some(snap);
        std::thread::sleep(std::time::Duration::from_millis(200));
    }
    assert!(
        detected,
        "应当能探测到实际监听的端口\n最后一次采样：{:?}\n日志：{:?}",
        last.map(|s| s.services),
        m.logs().iter().map(|l| &l.txt).collect::<Vec<_>>()
    );

    let t1 = Instant::now();
    for _ in 0..10 {
        m.snapshot();
    }
    let busy = t1.elapsed().as_secs_f64() * 100.0;
    m.stop("b1");

    println!(
        "snapshot 单次耗时：空载 {idle:.1}ms / 有进程在跑且端口已探到 {busy:.1}ms（节拍 1400ms）"
    );
    assert!(busy < 200.0, "单次采样 {busy:.1}ms 相对 1.4 秒节拍过重");

    let _ = std::fs::remove_dir_all(dir);
}
