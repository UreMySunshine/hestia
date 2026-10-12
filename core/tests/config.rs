//! 偏好设置里的日志行数，以及配置的导出、导入。

use std::path::PathBuf;
use std::process::Command;
use std::sync::Arc;
use std::time::{Duration, Instant};

use hestia_core::manager::{read_config_file, Manager};
use hestia_core::types::{
    AppConfig, ReadyKind, ServiceConfig, Stage, Step, StepKind, Workflow, DEFAULT_PROFILE,
    DEFAULT_WORKTREE, LOG_LINES_DEFAULT, LOG_LINES_MAX, LOG_LINES_MIN,
};

const EMPTY_CFG: &str =
    r#"{"services":[],"prefs":{"autostart":false,"autorestart":true,"notify":false,"quiet":true}}"#;

fn setup(tag: &str) -> (Arc<Manager>, PathBuf) {
    let dir = std::env::temp_dir().join(format!("hestia-config-{tag}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("config.json"), EMPTY_CFG).unwrap();
    let m = Manager::new_in(dir.clone(), Arc::new(|_: &str, _: String| {}));
    (m, dir)
}

fn svc(id: &str, cmd: &str) -> ServiceConfig {
    ServiceConfig {
        id: id.into(),
        name: id.into(),
        ic: "chip".into(),
        cmd: cmd.into(),
        stop: String::new(),
        cwd: String::new(),
        worktree: DEFAULT_WORKTREE.into(),
        worktrees: vec![],
        port: 0,
        auto_restart: false,
        env: vec![],
        profile: DEFAULT_PROFILE.into(),
        default_profile_name: String::new(),
        profiles: vec![],
    }
}

fn flow(id: &str, services: &[&str]) -> Workflow {
    Workflow {
        id: id.into(),
        name: id.into(),
        stages: vec![Stage {
            id: format!("{id}-s0"),
            steps: services
                .iter()
                .map(|s| Step {
                    id: format!("{id}-{s}"),
                    kind: StepKind::Service,
                    service: (*s).into(),
                    ready: ReadyKind::Delay,
                    ..Default::default()
                })
                .collect(),
        }],
        ..Default::default()
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

fn pgrep(pattern: &str) -> usize {
    let out = Command::new("pgrep").arg("-f").arg(pattern).output().unwrap();
    String::from_utf8_lossy(&out.stdout).lines().filter(|l| !l.trim().is_empty()).count()
}

#[test]
fn log_lines_are_clamped_and_trim_the_buffer() {
    let (m, dir) = setup("loglines");
    let mut prefs = m.config().prefs;
    prefs.log_lines = 5;
    m.set_prefs(prefs.clone());
    assert_eq!(m.config().prefs.log_lines, LOG_LINES_MIN, "低于下限按下限保存");
    prefs.log_lines = LOG_LINES_MAX * 10;
    m.set_prefs(prefs.clone());
    assert_eq!(m.config().prefs.log_lines, LOG_LINES_MAX, "高于上限按上限保存");

    m.save_service(svc("chatty", "seq 1 1500; sleep 918301"));
    m.start("chatty");
    wait_for("输出全部进入缓冲", Duration::from_secs(20), || {
        m.logs().iter().any(|l| l.txt == "1500")
    });
    assert!(m.logs().len() > LOG_LINES_MIN, "上限为 {LOG_LINES_MAX} 时应保留全部输出");

    prefs.log_lines = LOG_LINES_MIN;
    m.set_prefs(prefs);
    assert_eq!(m.logs().len(), LOG_LINES_MIN, "调小后立即丢掉最早的行");
    assert_eq!(m.logs().last().unwrap().txt, "1500", "保留的是最新的行");

    m.stop("chatty");
    wait_for("进程被回收", Duration::from_secs(20), || pgrep("sleep 918301") == 0);
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn prefs_missing_from_old_configs_take_defaults() {
    let (m, dir) = setup("defaults");
    let prefs = m.config().prefs;
    assert_eq!(prefs.log_lines, LOG_LINES_DEFAULT);
    assert!(prefs.auto_update, "旧配置没有这一项时默认每天检查更新");
    assert!(prefs.auto_install, "旧配置没有这一项时默认自动安装更新");

    let mut off = prefs;
    off.auto_update = false;
    off.auto_install = false;
    m.set_prefs(off);
    let saved = read_config_file(dir.join("config.json").to_str().unwrap()).unwrap();
    assert!(!saved.prefs.auto_update, "关掉后写回配置文件");
    assert!(!saved.prefs.auto_install, "关掉后写回配置文件");
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn exported_config_reads_back_and_other_files_are_rejected() {
    let (m, dir) = setup("export");
    m.save_service(svc("a", "true"));
    m.save_workflow(flow("wf", &["a"]));
    let file = dir.join("exported.json");
    m.export_config(file.to_str().unwrap()).unwrap();

    let back = read_config_file(file.to_str().unwrap()).unwrap();
    assert_eq!(back.services.len(), 1);
    assert_eq!(back.workflows[0].stages[0].steps[0].service, "a");

    let empty = dir.join("empty.json");
    std::fs::write(&empty, "{}").unwrap();
    assert!(read_config_file(empty.to_str().unwrap()).is_err(), "没有服务列表的对象不是配置文件");
    let text = dir.join("text.json");
    std::fs::write(&text, "hello").unwrap();
    assert!(read_config_file(text.to_str().unwrap()).is_err());
    assert!(read_config_file(dir.join("missing.json").to_str().unwrap()).is_err());
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn default_names_persist_and_import_without_changing_launch_targets() {
    let (m, dir) = setup("default-names");
    m.save_service(svc("web", "echo ready"));
    m.save_workflow(flow("wf", &["web"]));
    let mut renamed = m.config().services[0].clone();
    let before = renamed.launch_in(DEFAULT_PROFILE, DEFAULT_WORKTREE).unwrap();
    renamed.default_profile_name = "本地开发".into();
    renamed.worktrees[0].name = "项目目录".into();
    m.save_service(renamed);

    let saved = read_config_file(dir.join("config.json").to_str().unwrap()).unwrap();
    let service = &saved.services[0];
    let after = service.launch_in(DEFAULT_PROFILE, DEFAULT_WORKTREE).unwrap();
    assert_eq!(service.default_profile_name, "本地开发");
    assert_eq!(service.worktrees[0].name, "项目目录");
    assert!(before.same_target(&after));
    assert_eq!(before.cmd, after.cmd);
    assert_eq!(before.env, after.env);
    assert_eq!(after.profile, DEFAULT_PROFILE);
    assert_eq!(after.worktree, DEFAULT_WORKTREE);
    assert_eq!(after.name, "本地开发");
    assert_eq!(saved.workflows[0].stages[0].steps[0].service, "web");

    let file = dir.join("exported.json");
    m.export_config(file.to_str().unwrap()).unwrap();
    let exported = read_config_file(file.to_str().unwrap()).unwrap();
    let (other, other_dir) = setup("default-names-import");
    other.import_config(exported, true);
    let imported = other.config();
    assert_eq!(imported.services[0].default_profile_name, "本地开发");
    assert_eq!(imported.services[0].worktrees[0].name, "项目目录");
    assert_eq!(imported.workflows[0].stages[0].steps[0].service, "web");
    let _ = std::fs::remove_dir_all(dir);
    let _ = std::fs::remove_dir_all(other_dir);
}

#[test]
fn merging_overwrites_same_ids_and_keeps_the_rest() {
    let (m, dir) = setup("merge");
    m.save_service(svc("keep", "true"));
    m.save_service(svc("shared", "echo old"));
    let mut prefs = m.config().prefs;
    prefs.quiet = false;
    m.set_prefs(prefs);

    let mut incoming = AppConfig::default();
    incoming.services = vec![svc("shared", "echo new"), svc("added", "true")];
    incoming.workflows = vec![flow("wf", &["added", "ghost"])];
    incoming.prefs.quiet = true;
    m.import_config(incoming, false);

    let cfg = m.config();
    let ids: Vec<&str> = cfg.services.iter().map(|s| s.id.as_str()).collect();
    assert_eq!(ids, ["keep", "shared", "added"]);
    assert_eq!(cfg.services[1].cmd, "echo new", "同 id 的服务被覆盖");
    assert!(!cfg.prefs.quiet, "合并不改偏好");
    let steps = &cfg.workflows[0].stages[0].steps;
    assert_eq!(steps.len(), 1, "引用不存在服务的步骤被删掉");
    assert_eq!(steps[0].service, "added");
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn replacing_stops_services_that_are_no_longer_listed() {
    let (m, dir) = setup("replace");
    m.save_service(svc("old", "sleep 918302"));
    m.save_workflow(flow("old-flow", &["old"]));
    let mut prefs = m.config().prefs;
    prefs.autostart = true;
    m.set_prefs(prefs);
    m.start("old");
    wait_for("旧服务运行", Duration::from_secs(10), || m.is_running("old"));

    let mut incoming = AppConfig::default();
    incoming.services = vec![svc("new", "true")];
    incoming.prefs.autostart = false;
    incoming.prefs.log_lines = 2000;
    m.import_config(incoming, true);

    wait_for("不在导入内容里的服务被停掉", Duration::from_secs(20), || !m.is_running("old"));
    let cfg = m.config();
    let ids: Vec<&str> = cfg.services.iter().map(|s| s.id.as_str()).collect();
    assert_eq!(ids, ["new"]);
    assert!(cfg.workflows.is_empty());
    assert!(cfg.prefs.autostart, "开机自启保留本机设置");
    assert_eq!(cfg.prefs.log_lines, 2000, "其它偏好以导入内容为准");
    wait_for("进程被回收", Duration::from_secs(20), || pgrep("sleep 918302") == 0);
    let _ = std::fs::remove_dir_all(dir);
}
