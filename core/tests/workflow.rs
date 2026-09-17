//! 启动方案与工作流的集成测试：真的拉起进程，按方案、按阶段核对行为。

use std::path::PathBuf;
use std::process::Command;
use std::sync::Arc;
use std::time::{Duration, Instant};

use hestia_core::manager::Manager;
use hestia_core::types::{
    EnvVar, FlowState, Profile, ReadyKind, ServiceConfig, Stage, Step, StepKind, StepState,
    Workflow, WorkflowStatus, DEFAULT_PROFILE,
};

const EMPTY_CFG: &str =
    r#"{"services":[],"prefs":{"autostart":false,"autorestart":true,"notify":false,"quiet":true}}"#;

fn setup(tag: &str) -> (Arc<Manager>, PathBuf) {
    let dir = std::env::temp_dir().join(format!("hestia-flow-{tag}-{}", std::process::id()));
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
        proj: String::new(),
        ic: "chip".into(),
        cmd: cmd.into(),
        stop: String::new(),
        cwd: String::new(),
        port: 0,
        auto_restart: false,
        env: vec![],
        profile: DEFAULT_PROFILE.into(),
        profiles: vec![],
    }
}

fn service_step(id: &str, service: &str, ready: ReadyKind, seconds: u64) -> Step {
    Step {
        id: id.into(),
        kind: StepKind::Service,
        service: service.into(),
        ready,
        seconds,
        ..Default::default()
    }
}

fn command_step(id: &str, cmd: &str, cwd: &PathBuf, seconds: u64) -> Step {
    Step {
        id: id.into(),
        kind: StepKind::Command,
        name: id.into(),
        cmd: cmd.into(),
        cwd: cwd.display().to_string(),
        seconds,
        ..Default::default()
    }
}

fn workflow(id: &str, stages: Vec<Vec<Step>>) -> Workflow {
    Workflow {
        id: id.into(),
        name: id.into(),
        stages: stages
            .into_iter()
            .enumerate()
            .map(|(i, steps)| Stage { id: format!("s{i}"), steps })
            .collect(),
        ..Default::default()
    }
}

fn status(m: &Manager, id: &str) -> WorkflowStatus {
    m.snapshot().workflows.into_iter().find(|w| w.id == id).unwrap()
}

fn step_state(st: &WorkflowStatus, id: &str) -> (StepState, String) {
    let s = st.steps.iter().find(|s| s.id == id).unwrap();
    (s.state, s.detail.clone())
}

fn running_profile(m: &Manager, id: &str) -> String {
    m.snapshot()
        .services
        .into_iter()
        .find(|s| s.id == id)
        .map(|s| s.profile)
        .unwrap_or_default()
}

fn pid(m: &Manager, id: &str) -> u32 {
    m.snapshot().services.into_iter().find(|s| s.id == id).map(|s| s.pid).unwrap_or(0)
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
    String::from_utf8_lossy(&out.stdout)
        .lines()
        .filter(|l| !l.trim().is_empty())
        .count()
}

fn logged(m: &Manager, text: &str) -> bool {
    m.logs().iter().any(|l| l.txt.contains(text))
}

#[test]
fn profile_env_reaches_the_process_and_switching_replaces_it() {
    let (m, dir) = setup("switch");
    let mut s = svc("p1", "echo client=$HESTIA_T_CLIENT; sleep 918281");
    s.env = vec![EnvVar { k: "HESTIA_T_CLIENT".into(), v: "dev".into() }];
    s.profiles = vec![Profile {
        id: "test".into(),
        name: "test 环境".into(),
        env: vec![EnvVar { k: "HESTIA_T_CLIENT".into(), v: "test".into() }],
        ..Default::default()
    }];
    m.save_service(s);

    m.start_as("p1", Some("test"));
    wait_for("按 test 方案输出", Duration::from_secs(15), || logged(&m, "client=test"));
    assert_eq!(running_profile(&m, "p1"), "test");
    assert_eq!(m.config().services[0].profile, "test", "按方案启动后记为当前方案");
    let first = pid(&m, "p1");

    m.start_as("p1", Some(DEFAULT_PROFILE));
    wait_for("切换后按默认方案输出", Duration::from_secs(30), || logged(&m, "client=dev"));
    wait_for("运行中的方案变为默认", Duration::from_secs(10), || {
        running_profile(&m, "p1") == DEFAULT_PROFILE
    });
    assert_ne!(pid(&m, "p1"), first, "切换方案应换一个进程");
    assert_eq!(m.config().services[0].profile, DEFAULT_PROFILE);

    m.stop("p1");
    wait_for("进程被回收", Duration::from_secs(20), || pgrep("sleep 918281") == 0);
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn restart_keeps_the_profile_the_process_was_started_with() {
    let (m, dir) = setup("restart");
    let mut s = svc("p2", "echo marker=$HESTIA_T_MARK; sleep 918286");
    s.profiles = vec![Profile {
        id: "alt".into(),
        name: "alt".into(),
        env: vec![EnvVar { k: "HESTIA_T_MARK".into(), v: "alt".into() }],
        ..Default::default()
    }];
    m.save_service(s.clone());
    m.start_as("p2", Some("alt"));
    wait_for("按 alt 启动", Duration::from_secs(15), || logged(&m, "marker=alt"));
    let first = pid(&m, "p2");

    // 运行期间把当前方案改回默认，重启仍应沿用进程启动时的方案
    s.profile = DEFAULT_PROFILE.into();
    m.save_service(s);
    m.restart("p2");
    wait_for("重启后换了进程", Duration::from_secs(30), || {
        let p = pid(&m, "p2");
        p != 0 && p != first
    });
    assert_eq!(running_profile(&m, "p2"), "alt");

    m.stop("p2");
    wait_for("进程被回收", Duration::from_secs(20), || pgrep("sleep 918286") == 0);
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn workflow_runs_stages_in_order_and_waits_for_ports() {
    let (m, dir) = setup("order");
    let marker = dir.join("stage-one-done");
    m.save_service(svc(
        "api",
        "python3 -c 'import socket, time; time.sleep(1); s = socket.socket(); s.bind((\"127.0.0.1\", 19881)); s.listen(); time.sleep(600)'",
    ));
    // 第一阶段没做完就启动的话，这里读不到标记文件，进程立即以非 0 退出
    m.save_service(svc("web", &format!("cat {} && sleep 918282", marker.display())));
    m.save_workflow(workflow(
        "wf",
        vec![
            vec![
                service_step("api-step", "api", ReadyKind::Port, 30),
                command_step("prep", "sleep 1 && touch stage-one-done", &dir, 30),
            ],
            vec![service_step("web-step", "web", ReadyKind::Delay, 1)],
        ],
    ));

    m.start_workflow("wf");
    wait_for("工作流完成", Duration::from_secs(60), || {
        status(&m, "wf").state != FlowState::Running
    });

    let st = status(&m, "wf");
    assert_eq!(st.state, FlowState::Done, "失败原因：{}", st.message);
    let (state, detail) = step_state(&st, "api-step");
    assert_eq!(state, StepState::Done);
    assert!(detail.contains("19881"), "应报告实际端口，实际 {detail}");
    assert_eq!(step_state(&st, "prep"), (StepState::Done, "退出码 0".into()));
    assert_eq!(step_state(&st, "web-step").0, StepState::Done);
    assert_eq!((st.members, st.matched), (2, 2));
    assert!(m.is_running("web"));
    assert!(logged(&m, "[wf] 工作流开始运行"));
    assert!(logged(&m, "[wf] 工作流全部就绪"));

    m.stop_workflow("wf");
    wait_for("两个服务都被停止", Duration::from_secs(30), || {
        !m.is_running("api") && !m.is_running("web")
    });
    let st = status(&m, "wf");
    assert_eq!(st.state, FlowState::Stopped);
    assert_eq!(step_state(&st, "prep"), (StepState::Stopped, "已停止".into()), "执行过的命令随工作流停止");
    wait_for("子进程被回收", Duration::from_secs(20), || pgrep("sleep 918282") == 0);
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn failed_stage_skips_later_stages_and_keeps_started_services() {
    let (m, dir) = setup("fail");
    m.save_service(svc("ok", "sleep 918283"));
    m.save_service(svc("bad", "sleep 0.3; exit 4"));
    m.save_workflow(workflow(
        "wf",
        vec![
            vec![
                service_step("ok-step", "ok", ReadyKind::Delay, 1),
                service_step("bad-step", "bad", ReadyKind::Delay, 3),
            ],
            vec![command_step("later", "touch later-ran", &dir, 10)],
        ],
    ));

    m.start_workflow("wf");
    wait_for("工作流结束", Duration::from_secs(30), || {
        status(&m, "wf").state != FlowState::Running
    });

    let st = status(&m, "wf");
    assert_eq!(st.state, FlowState::Failed);
    let (state, detail) = step_state(&st, "bad-step");
    assert_eq!(state, StepState::Failed);
    assert!(detail.contains("退出码 4"), "失败原因应带退出码，实际 {detail}");
    assert!(st.message.contains("bad"), "失败摘要应指明哪个服务，实际 {}", st.message);
    assert_eq!(step_state(&st, "ok-step").0, StepState::Done, "同阶段其它步骤照常完成");
    assert_eq!(step_state(&st, "later").0, StepState::Skipped);
    assert!(!dir.join("later-ran").exists(), "失败后不应执行后续阶段");
    assert!(m.is_running("ok"), "已启动的服务保持运行");
    let failure = m
        .logs()
        .into_iter()
        .find(|l| l.sid == "wf" && l.txt.starts_with("[wf] 工作流在阶段 1 失败："))
        .expect("失败应写入以工作流为来源的记录，供首页列出");
    assert_eq!(failure.lvl, "ERROR");
    assert!(failure.txt.contains("退出码 4"), "记录应带失败原因，实际 {}", failure.txt);

    m.stop("ok");
    wait_for("进程被回收", Duration::from_secs(20), || pgrep("sleep 918283") == 0);
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn command_step_is_killed_when_it_exceeds_the_timeout() {
    let (m, dir) = setup("timeout");
    m.save_workflow(workflow("wf", vec![vec![command_step("slow", "sleep 918284", &dir, 1)]]));

    m.start_workflow("wf");
    wait_for("工作流结束", Duration::from_secs(20), || {
        status(&m, "wf").state != FlowState::Running
    });

    let st = status(&m, "wf");
    assert_eq!(st.state, FlowState::Failed);
    let (state, detail) = step_state(&st, "slow");
    assert_eq!(state, StepState::Failed);
    assert!(detail.contains("1 秒"), "应说明超时，实际 {detail}");
    wait_for("超时的命令被回收", Duration::from_secs(10), || pgrep("sleep 918284") == 0);
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn stopping_a_workflow_cancels_the_running_command() {
    let (m, dir) = setup("cancel");
    m.save_workflow(workflow(
        "wf",
        vec![
            vec![command_step("long", "sleep 918285", &dir, 120)],
            vec![command_step("after", "touch after-ran", &dir, 10)],
        ],
    ));

    m.start_workflow("wf");
    wait_for("命令开始执行", Duration::from_secs(15), || pgrep("sleep 918285") > 0);
    m.stop_workflow("wf");

    wait_for("命令被回收", Duration::from_secs(15), || pgrep("sleep 918285") == 0);
    let st = status(&m, "wf");
    assert_eq!(st.state, FlowState::Stopped);
    assert_eq!(step_state(&st, "after").0, StepState::Skipped);
    std::thread::sleep(Duration::from_millis(500));
    assert!(!dir.join("after-ran").exists(), "停止后不应继续执行");
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn workflow_uses_the_step_profile_without_changing_the_current_one() {
    let (m, dir) = setup("keep-current");
    let mut s = svc("p3", "echo mode=$HESTIA_T_MODE; sleep 918287");
    s.profiles = vec![Profile {
        id: "alt".into(),
        name: "alt".into(),
        env: vec![EnvVar { k: "HESTIA_T_MODE".into(), v: "alt".into() }],
        ..Default::default()
    }];
    m.save_service(s);
    let mut step = service_step("s", "p3", ReadyKind::Delay, 0);
    step.profile = "alt".into();
    m.save_workflow(workflow("wf", vec![vec![step]]));

    m.start_workflow("wf");
    wait_for("工作流结束", Duration::from_secs(30), || {
        status(&m, "wf").state != FlowState::Running
    });
    let st = status(&m, "wf");
    assert_eq!(st.state, FlowState::Done, "失败原因：{}", st.message);
    assert_eq!(running_profile(&m, "p3"), "alt");
    assert_eq!(m.config().services[0].profile, DEFAULT_PROFILE, "工作流不改服务的当前方案");

    m.stop_workflow("wf");
    wait_for("进程被回收", Duration::from_secs(20), || pgrep("sleep 918287") == 0);
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn stopping_a_workflow_keeps_services_another_started_workflow_uses() {
    let (m, dir) = setup("shared");
    m.save_service(svc("shared", "sleep 918288"));
    m.save_service(svc("own", "sleep 918289"));
    m.save_service(svc("extra", "sleep 918291"));
    m.save_workflow(workflow(
        "a",
        vec![
            vec![service_step("a1", "shared", ReadyKind::Delay, 0)],
            vec![service_step("a2", "own", ReadyKind::Delay, 0)],
        ],
    ));
    m.save_workflow(workflow(
        "b",
        vec![vec![
            service_step("b1", "shared", ReadyKind::Delay, 0),
            service_step("b2", "extra", ReadyKind::Delay, 0),
        ]],
    ));
    let finished = |id: &str| status(&m, id).state != FlowState::Running;

    m.start_workflow("b");
    wait_for("工作流 b 结束", Duration::from_secs(30), || finished("b"));
    // b 只剩部分服务在运行，仍算作在使用 shared
    m.stop("extra");
    wait_for("extra 停止", Duration::from_secs(20), || !m.is_running("extra"));
    m.start_workflow("a");
    wait_for("工作流 a 结束", Duration::from_secs(30), || finished("a"));
    assert_eq!(status(&m, "a").state, FlowState::Done);
    let b = status(&m, "b");
    assert_eq!((b.state, b.members, b.matched), (FlowState::Done, 2, 1));

    m.stop_workflow("a");
    let noted = |text: &str| status(&m, "a").events.iter().any(|e| e.text == text);
    wait_for("跳过共用服务的记录", Duration::from_secs(30), || {
        noted("shared 仍被「b」使用，未停止")
    });
    wait_for("own 被停止", Duration::from_secs(30), || noted("own 已停止"));
    assert!(!m.is_running("own"));
    assert!(m.is_running("shared"), "b 仍在使用的服务不应被停止");
    let st = status(&m, "a");
    assert_eq!(step_state(&st, "a2"), (StepState::Stopped, "已停止".into()));
    assert_eq!(step_state(&st, "a1").0, StepState::Done, "服务仍在运行，步骤保持完成");
    assert_eq!((st.state, st.matched), (FlowState::Stopped, 1));

    m.stop_workflow("b");
    wait_for("共用服务随 b 停止", Duration::from_secs(30), || !m.is_running("shared"));
    wait_for("进程被回收", Duration::from_secs(20), || pgrep("sleep 9182(88|89|91)") == 0);
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn a_workflow_nobody_started_does_not_keep_services() {
    let (m, dir) = setup("passive");
    m.save_service(svc("both", "sleep 918292"));
    m.save_workflow(workflow("a", vec![vec![service_step("a1", "both", ReadyKind::Delay, 0)]]));
    m.save_workflow(workflow("b", vec![vec![service_step("b1", "both", ReadyKind::Delay, 0)]]));

    m.start_workflow("a");
    wait_for("工作流 a 结束", Duration::from_secs(30), || {
        status(&m, "a").state != FlowState::Running
    });
    let b = status(&m, "b");
    assert_eq!(b.state, FlowState::Idle);
    assert_eq!((b.members, b.matched), (1, 1));
    let passive = b.steps.iter().find(|s| s.id == "b1").unwrap();
    assert_eq!(passive.state, StepState::Done, "服务已按方案运行，没执行过的步骤也显示完成");
    assert_eq!(passive.elapsed, 0.0, "不是本工作流执行的步骤不报耗时");

    m.stop_workflow("a");
    wait_for("没人启动的 b 不占用服务", Duration::from_secs(30), || !m.is_running("both"));
    assert_eq!(step_state(&status(&m, "b"), "b1").0, StepState::Pending);
    assert_eq!(step_state(&status(&m, "a"), "a1"), (StepState::Stopped, "已停止".into()));

    // 停止后服务又被拉起，停止过的工作流跟着显示完成
    m.start_workflow("b");
    wait_for("工作流 b 结束", Duration::from_secs(30), || {
        status(&m, "b").state != FlowState::Running
    });
    assert_eq!(step_state(&status(&m, "a"), "a1").0, StepState::Done);

    m.stop_workflow("b");
    wait_for("进程被回收", Duration::from_secs(20), || pgrep("sleep 918292") == 0);
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn a_finished_step_follows_its_service_after_the_run() {
    let (m, dir) = setup("drift");
    m.save_service(svc("solo", "sleep 918290"));
    m.save_service(svc("crash", "sleep 2; exit 3"));
    m.save_workflow(workflow(
        "wf",
        vec![vec![
            service_step("s", "solo", ReadyKind::Delay, 0),
            service_step("c", "crash", ReadyKind::Delay, 0),
        ]],
    ));

    m.start_workflow("wf");
    wait_for("工作流结束", Duration::from_secs(30), || {
        status(&m, "wf").state != FlowState::Running
    });
    let st = status(&m, "wf");
    assert_eq!(st.state, FlowState::Done, "失败原因：{}", st.message);
    assert_eq!(step_state(&st, "s").0, StepState::Done);

    wait_for("服务异常退出后步骤显示失败", Duration::from_secs(20), || {
        step_state(&status(&m, "wf"), "c") == (StepState::Failed, "异常退出".into())
    });

    m.stop("solo");
    wait_for("单独停掉服务后步骤不再显示完成", Duration::from_secs(20), || {
        step_state(&status(&m, "wf"), "s").0 == StepState::Stopped
    });
    assert_eq!(step_state(&status(&m, "wf"), "s"), (StepState::Stopped, "已停止".into()));
    assert_eq!(status(&m, "wf").state, FlowState::Done, "工作流本身的状态不变");

    m.start("solo");
    wait_for("服务重新运行后步骤恢复完成", Duration::from_secs(20), || {
        step_state(&status(&m, "wf"), "s").0 == StepState::Done
    });

    // 停止工作流时，异常退出的服务一并清回已停止
    m.stop_workflow("wf");
    wait_for("两个步骤都显示已停止", Duration::from_secs(30), || {
        let st = status(&m, "wf");
        step_state(&st, "s").0 == StepState::Stopped && step_state(&st, "c").0 == StepState::Stopped
    });
    wait_for("进程被回收", Duration::from_secs(20), || pgrep("sleep 918290") == 0);
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn deleting_a_service_removes_its_steps() {
    let (m, dir) = setup("delete");
    m.save_service(svc("gone", "true"));
    m.save_service(svc("kept", "true"));
    m.save_workflow(workflow(
        "wf",
        vec![
            vec![service_step("a", "gone", ReadyKind::Delay, 0)],
            vec![
                service_step("b", "gone", ReadyKind::Delay, 0),
                service_step("c", "kept", ReadyKind::Delay, 0),
            ],
        ],
    ));

    m.delete_service("gone".into());

    let wf = m.config().workflows.into_iter().next().unwrap();
    assert_eq!(wf.stages.len(), 1, "只剩被删服务的阶段应一并移除");
    let ids: Vec<String> = wf.stages[0].steps.iter().map(|s| s.id.clone()).collect();
    assert_eq!(ids, vec!["c".to_string()]);
    let _ = std::fs::remove_dir_all(dir);
}
