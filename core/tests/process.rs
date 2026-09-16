//! 进程托管的集成测试：真的把进程拉起来，再确认能连同子进程一起收干净。

use std::path::PathBuf;
use std::process::Command;
use std::sync::Arc;
use std::time::{Duration, Instant};

use hestia_core::manager::Manager;
use hestia_core::types::{RunState, ServiceConfig};

const EMPTY_CFG: &str =
    r#"{"services":[],"prefs":{"autostart":false,"autorestart":true,"notify":false,"quiet":true}}"#;

fn setup(tag: &str) -> (Arc<Manager>, PathBuf) {
    let dir = std::env::temp_dir().join(format!("hestia-test-{tag}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("config.json"), EMPTY_CFG).unwrap();

    let m = Manager::new_in(dir.clone(), std::sync::Arc::new(|_: &str, _: String| {}));
    (m, dir)
}

fn svc(id: &str, cmd: &str, auto_restart: bool) -> ServiceConfig {
    ServiceConfig {
        id: id.into(),
        name: id.into(),
        proj: "test".into(),
        ic: "chip".into(),
        cmd: cmd.into(),
        stop: String::new(),
        cwd: String::new(),
        port: 0,
        auto_restart,
        env: vec![],
    }
}

fn wait_for(label: &str, limit: Duration, mut f: impl FnMut() -> bool) {
    let deadline = Instant::now() + limit;
    while Instant::now() < deadline {
        if f() {
            return;
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    panic!("等待超时：{label}");
}

/// 命令行里含指定串的进程数
fn pgrep(pattern: &str) -> usize {
    let out = Command::new("pgrep")
        .arg("-f")
        .arg(pattern)
        .output()
        .unwrap();
    String::from_utf8_lossy(&out.stdout)
        .lines()
        .filter(|l| !l.trim().is_empty())
        .count()
}

#[test]
fn starts_captures_output_and_reaps_children() {
    let (m, dir) = setup("basic");
    // sleep 的时长当作唯一标记，用来确认子进程也被收掉
    m.save_service(svc("t1", "echo hello-hestia; sleep 918273", false));

    m.start("t1");

    wait_for("进程启动", Duration::from_secs(15), || {
        m.is_running("t1")
    });
    wait_for("标准输出被采集", Duration::from_secs(15), || {
        m.logs().iter().any(|l| l.txt.contains("hello-hestia"))
    });
    wait_for("子进程出现", Duration::from_secs(15), || {
        pgrep("sleep 918273") > 0
    });

    let snap = m.snapshot();
    let st = snap.services.iter().find(|s| s.id == "t1").unwrap();
    assert_eq!(st.state, RunState::Running);
    assert!(st.pid > 0, "运行中应有 pid");
    assert!(st.mem > 0.0, "运行中应能采到内存占用，实际 {}", st.mem);

    m.stop("t1");

    wait_for("状态转为已停止", Duration::from_secs(20), || {
        !m.is_running("t1")
    });
    wait_for("子进程被回收", Duration::from_secs(20), || {
        pgrep("sleep 918273") == 0
    });

    let snap = m.snapshot();
    let st = snap.services.iter().find(|s| s.id == "t1").unwrap();
    assert_eq!(st.state, RunState::Stopped);
    assert_eq!(st.pid, 0);

    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn records_crash_and_retries() {
    let (m, dir) = setup("crash");
    m.save_service(svc("t2", "echo 要炸了; exit 3", true));

    m.start("t2");

    wait_for("记录到异常退出", Duration::from_secs(15), || {
        m.logs()
            .iter()
            .any(|l| l.lvl == "ERROR" && l.txt.contains("退出码 3"))
    });
    wait_for("触发自动重启", Duration::from_secs(15), || {
        let snap = m.snapshot();
        snap.services
            .iter()
            .find(|s| s.id == "t2")
            .map(|s| s.restarts >= 1)
            .unwrap_or(false)
    });

    let snap = m.snapshot();
    let st = snap.services.iter().find(|s| s.id == "t2").unwrap();
    assert!(st.errors >= 1, "异常退出应累计错误数");
    assert!(!st.last_error.is_empty(), "异常退出应记录原因");

    m.delete_service("t2".into());
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn refuses_missing_working_directory() {
    let (m, dir) = setup("cwd");
    let mut s = svc("t3", "echo never", false);
    s.cwd = "/definitely/not/here/hestia".into();
    m.save_service(s);

    m.start("t3");

    wait_for("目录不存在时报错", Duration::from_secs(10), || {
        m.logs().iter().any(|l| l.txt.contains("工作目录不存在"))
    });
    assert!(!m.is_running("t3"));

    let _ = std::fs::remove_dir_all(dir);
}

/// 全新安装（配置目录里还没有 config.json）应当得到空配置，
/// 不能再写入示例服务——示例路径在别人机器上一个都不存在
#[test]
fn first_run_starts_with_no_services() {
    let dir = std::env::temp_dir().join(format!("hestia-test-fresh-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);

    let m = Manager::new_in(dir.clone(), std::sync::Arc::new(|_: &str, _: String| {}));

    let cfg = m.config();
    assert!(
        cfg.services.is_empty(),
        "首次运行不应有服务，实际 {}",
        cfg.services.len()
    );
    // 偏好项仍走各自的默认值，自动重启默认是开的
    assert!(cfg.prefs.autorestart);

    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn config_survives_restart_of_manager() {
    let (m, dir) = setup("persist");
    m.save_service(svc("t4", "true", false));
    assert_eq!(m.config().services.len(), 1);

    // 新建一个 Manager 指向同一目录，应当读回刚写下的配置
    let m2 = Manager::new_in(dir.clone(), std::sync::Arc::new(|_: &str, _: String| {}));
    assert_eq!(m2.config().services.len(), 1);
    assert_eq!(m2.config().services[0].id, "t4");

    let _ = std::fs::remove_dir_all(dir);
}

/// 应用被强杀时来不及清理，下次启动必须把上一轮残留的进程收掉
#[test]
fn reaps_orphans_left_by_a_previous_run() {
    let (m, dir) = setup("orphan");
    // 独特的时长当标记，便于用 pgrep 定位
    m.save_service(svc("t5", "sleep 918274", false));
    m.start("t5");

    wait_for("进程启动", Duration::from_secs(40), || {
        m.is_running("t5")
    });
    wait_for("子进程出现", Duration::from_secs(40), || {
        pgrep("sleep 918274") > 0
    });

    // 运行态应当已经落盘
    let running = dir.join("running.json");
    wait_for("运行态落盘", Duration::from_secs(5), || {
        std::fs::read_to_string(&running)
            .map(|s| s.contains("t5"))
            .unwrap_or(false)
    });

    // 模拟应用被强杀：Manager 还在，但新起一个实例指向同一目录，
    // 它在构造时应当读到上一轮的记录并回收这些进程
    let _m2 = Manager::new_in(dir.clone(), std::sync::Arc::new(|_: &str, _: String| {}));

    wait_for("残留进程被回收", Duration::from_secs(40), || {
        pgrep("sleep 918274") == 0
    });

    let _ = std::fs::remove_dir_all(dir);
}

/// pid 被复用时不能误杀无关进程：命令行对不上就跳过
#[test]
fn does_not_kill_when_command_line_differs() {
    let dir = std::env::temp_dir().join(format!("hestia-test-reuse-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("config.json"), EMPTY_CFG).unwrap();

    // 起一个无关进程，冒充「上一轮残留」，但记录一条对不上的命令
    let mut victim = Command::new("sleep").arg("918275").spawn().unwrap();
    let pid = victim.id();
    std::fs::write(
        dir.join("running.json"),
        format!(r#"[{{"id":"ghost","pid":{pid},"pgid":{pid},"cmd":"这条命令根本对不上"}}]"#),
    )
    .unwrap();

    let _m = Manager::new_in(dir.clone(), std::sync::Arc::new(|_: &str, _: String| {}));

    std::thread::sleep(Duration::from_millis(800));
    assert!(pgrep("sleep 918275") > 0, "命令行对不上时不应该动这个进程");

    let _ = victim.kill();
    let _ = victim.wait();
    let _ = std::fs::remove_dir_all(dir);
}

/// 端口应当按进程树实际监听的情况推断，而不是只看配置值
#[test]
fn detects_the_port_actually_listened_on() {
    let (m, dir) = setup("port");
    // 故意把配置端口写成另一个值，验证探测到的是实际那个。
    // 不用 http.server：它绑定端口后要先反查主机名才开始监听，CI 机器上这一步会卡住二十秒以上
    let mut s = svc(
        "t6",
        "python3 -c 'import socket, time; s = socket.socket(); s.bind((\"127.0.0.1\", 19877)); s.listen(); time.sleep(600)'",
        false,
    );
    s.port = 19999;
    m.save_service(s);
    m.start("t6");

    wait_for("探测到实际端口", Duration::from_secs(40), || {
        m.snapshot()
            .services
            .iter()
            .any(|x| x.id == "t6" && x.ports.contains(&19877))
    });

    let snap = m.snapshot();
    let st = snap.services.iter().find(|s| s.id == "t6").unwrap();
    assert!(st.ports.contains(&19877), "应探测到实际监听的 19877");
    assert!(
        !st.port_open,
        "配置的 19999 并没有被本服务监听，port_open 应为假"
    );

    m.stop("t6");
    let _ = std::fs::remove_dir_all(dir);
}
