//! 核对 CPU 口径：sysinfo 的 cpu_usage 是「占单核的百分比」，
//! 而 Hestia 汇总的是整棵进程树，因此多进程 / 多线程时超过 100% 是正常的。
use std::time::Duration;

use hestia_core::manager::Manager;
use hestia_core::types::{ServiceConfig, Snapshot, DEFAULT_PROFILE};

fn setup(tag: &str) -> (std::sync::Arc<Manager>, std::path::PathBuf) {
    let dir = std::env::temp_dir().join(format!("hestia-{tag}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("config.json"),
        r#"{"services":[],"prefs":{"autostart":false,"autorestart":true,"notify":false,"quiet":true}}"#).unwrap();
    let m = Manager::new_in(dir.clone(), std::sync::Arc::new(|_: &str, _: String| {}));
    (m, dir)
}

fn cpu(s: &Snapshot, id: &str) -> f32 {
    s.services
        .iter()
        .find(|x| x.id == id)
        .map(|x| x.cpu)
        .unwrap_or(0.0)
}

/// 采样间隔过短时不能重新计算，否则 CPU 差值算出来的数没有意义。
/// 主窗口和菜单栏窗口各有一个轮询，两者会撞在一起。
#[test]
fn back_to_back_snapshots_reuse_the_last_sample() {
    let (m, dir) = setup("throttle");
    m.save_service(ServiceConfig {
        id: "burn".into(),
        name: "burn".into(),
        proj: "t".into(),
        ic: "chip".into(),
        cmd: "while :; do :; done".into(),
        stop: String::new(),
        cwd: String::new(),
        port: 0,
        auto_restart: false,
        env: vec![],
        profile: DEFAULT_PROFILE.into(),
        profiles: vec![],
    });
    m.start("burn");
    std::thread::sleep(Duration::from_secs(2));

    m.snapshot();
    std::thread::sleep(Duration::from_millis(1400));
    let normal = cpu(&m.snapshot(), "burn");
    // 紧接着再采一次，应当拿到同一份结果而不是重算
    let tight = cpu(&m.snapshot(), "burn");

    // 这条只是防止下面的相等断言变成 0 == 0 的空转，不是在核对具体量级：
    // CI 的机器核数少且有争用，同一个忙循环在本机读到 90~101%，在 runner 上只有 49%
    assert!(normal > 10.0, "忙循环应当读到非零占用，实际 {normal:.0}%");
    assert_eq!(
        normal, tight,
        "间隔不足 400ms 时应复用上一次结果，实际 {normal:.0}% vs {tight:.0}%"
    );

    m.stop("burn");
    std::thread::sleep(Duration::from_secs(1));
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn tree_sum_scales_with_busy_process_count() {
    let (m, dir) = setup("cores");

    // 一个忙循环 vs 四个并行忙循环
    for (id, n) in [("one", 1), ("four", 4)] {
        let body = (0..n)
            .map(|_| "(while :; do :; done) &")
            .collect::<Vec<_>>()
            .join(" ");
        m.save_service(ServiceConfig {
            id: id.into(),
            name: id.into(),
            proj: "t".into(),
            ic: "chip".into(),
            cmd: format!("{body} wait"),
            stop: String::new(),
            cwd: String::new(),
            port: 0,
            auto_restart: false,
            env: vec![],
            profile: DEFAULT_PROFILE.into(),
            profiles: vec![],
        });
        m.start(id);
    }
    std::thread::sleep(Duration::from_secs(2));
    m.snapshot();
    std::thread::sleep(Duration::from_millis(1400));
    let s = m.snapshot();

    assert!(
        cpu(&s, "four") > cpu(&s, "one") * 2.0,
        "四个忙循环应当明显高于一个"
    );
    println!("单个忙循环：{:.0}%", cpu(&s, "one"));
    println!("四个忙循环：{:.0}%", cpu(&s, "four"));
    println!(
        "本机逻辑核心数：{}",
        std::thread::available_parallelism()
            .map(|n| n.get())
            .unwrap_or(0)
    );

    m.stop("one");
    m.stop("four");
    std::thread::sleep(Duration::from_secs(1));
    let _ = std::fs::remove_dir_all(dir);
}
