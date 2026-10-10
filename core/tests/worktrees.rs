use std::path::PathBuf;
use std::sync::Arc;
use std::time::{Duration, Instant};

use hestia_core::manager::{read_config_file, Manager};
use hestia_core::types::*;

fn setup(tag: &str, command: &str) -> (Arc<Manager>, PathBuf, ServiceConfig) {
    let dir = std::env::temp_dir().join(format!("hestia-worktrees-{tag}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    for name in ["main", "alt"] {
        std::fs::create_dir_all(dir.join(name)).unwrap();
    }
    let dir = dir.canonicalize().unwrap();
    let svc: ServiceConfig = serde_json::from_value(serde_json::json!({
        "id": "web", "name": "web", "proj": "", "ic": "web", "cmd": command,
        "stop": "", "cwd": dir.join("main"), "port": 0, "autoRestart": false, "env": [],
        "worktree": "default", "worktrees": [
            { "id": "default", "name": "主目录", "cwd": dir.join("main") },
            { "id": "alt", "name": "功能开发", "cwd": dir.join("alt") }
        ]
    }))
    .unwrap();
    let m = Manager::new_in(dir.clone(), Arc::new(|_, _| {}));
    m.save_service(svc.clone());
    (m, dir, svc)
}

fn wait(label: &str, mut condition: impl FnMut() -> bool) {
    let deadline = Instant::now() + Duration::from_secs(25);
    while Instant::now() < deadline {
        if condition() {
            return;
        }
        std::thread::sleep(Duration::from_millis(50));
    }
    panic!("等待超时：{label}");
}

fn service(m: &Manager) -> ServiceStatus {
    m.snapshot()
        .services
        .into_iter()
        .find(|s| s.id == "web")
        .unwrap()
}

fn flow(m: &Manager) -> WorkflowStatus {
    m.snapshot()
        .workflows
        .into_iter()
        .find(|w| w.id == "wf")
        .unwrap()
}

fn workflow(steps: Vec<Vec<Step>>) -> Workflow {
    Workflow {
        id: "wf".into(),
        name: "开发环境".into(),
        stages: steps
            .into_iter()
            .enumerate()
            .map(|(i, steps)| Stage {
                id: i.to_string(),
                steps,
            })
            .collect(),
        ..Default::default()
    }
}

fn service_step() -> Step {
    Step {
        id: "web-step".into(),
        service: "web".into(),
        ready: ReadyKind::Delay,
        ..Default::default()
    }
}

fn cleanup(m: &Arc<Manager>, dir: &PathBuf) {
    m.stop("web");
    wait("服务停止", || !m.is_running("web"));
    std::fs::remove_dir_all(dir).unwrap();
}

#[test]
fn old_directories_migrate_on_load_and_import_without_changing_references() {
    let (m, dir, _) = setup("migration", "true");
    let mut raw = serde_json::to_value(m.config()).unwrap();
    let old = &mut raw["services"][0];
    old.as_object_mut().unwrap().remove("worktree");
    old.as_object_mut().unwrap().remove("worktrees");
    raw["workflows"] = serde_json::to_value(vec![workflow(vec![vec![service_step()]])]).unwrap();
    let path = dir.join("old.json");
    std::fs::write(&path, serde_json::to_vec(&raw).unwrap()).unwrap();
    let cfg = read_config_file(path.to_str().unwrap()).unwrap();
    assert_eq!(cfg.services[0].worktree, DEFAULT_WORKTREE);
    assert_eq!(
        cfg.services[0].worktrees[0].cwd,
        dir.join("main").display().to_string()
    );
    assert_eq!(cfg.workflows[0].stages[0].steps[0].service, "web");
    assert_eq!(cfg.workflows[0].stages[0].steps[0].worktree, "");
    assert!(serde_json::to_value(&cfg.services[0])
        .unwrap()
        .get("proj")
        .is_none());
    m.import_config(cfg, true);
    assert_eq!(m.config().services[0].worktrees.len(), 1);
    std::fs::write(dir.join("config.json"), serde_json::to_vec(&raw).unwrap()).unwrap();
    let loaded = Manager::new_in(dir.clone(), Arc::new(|_, _| {}));
    let saved: AppConfig =
        serde_json::from_slice(&std::fs::read(dir.join("config.json")).unwrap()).unwrap();
    assert_eq!(loaded.config().services[0].worktrees.len(), 1);
    assert_eq!(saved.services[0].worktrees.len(), 1);
    cleanup(&loaded, &dir);
}

#[test]
fn switching_directory_replaces_the_process_and_invalid_targets_keep_it_running() {
    let (m, dir, _) = setup("switch", "pwd; exec sleep 918401");
    m.start("web");
    let first = service(&m).pid;
    m.start_in("web", None, Some("alt"));
    wait("新目录启动", || service(&m).worktree == "alt");
    let running = service(&m);
    assert_ne!(running.pid, first);
    assert_eq!(running.cwd, dir.join("alt").display().to_string());
    assert_eq!(m.config().services[0].worktree, "alt");
    m.start_in("web", None, Some("alt"));
    assert_eq!(service(&m).pid, running.pid);
    m.start_in("web", None, Some("removed"));
    assert_eq!(service(&m).pid, running.pid);
    assert_eq!(m.config().services[0].worktree, "alt");
    cleanup(&m, &dir);
}

#[test]
fn selecting_a_profile_and_directory_does_not_start_a_stopped_service() {
    let (m, dir, mut svc) = setup("selection", "exec sleep 918408");
    svc.profiles.push(Profile {
        id: "test".into(),
        name: "测试".into(),
        ..Default::default()
    });
    m.save_service(svc);
    m.select_profile("web", "test");
    m.select_worktree("web", "alt");
    assert!(!m.is_running("web"));
    assert_eq!(m.config().services[0].profile, "test");
    assert_eq!(m.config().services[0].worktree, "alt");
    m.select_profile("web", "removed");
    assert_eq!(m.config().services[0].profile, "test");
    m.start("web");
    assert_eq!(service(&m).profile, "test");
    assert_eq!(service(&m).worktree, "alt");
    cleanup(&m, &dir);
}

#[test]
fn workflows_use_saved_profile_and_directory_or_follow_the_current_selection() {
    let (m, dir, mut svc) = setup("saved-selection", "exec sleep 918409");
    svc.profiles.push(Profile {
        id: "test".into(),
        name: "测试".into(),
        ..Default::default()
    });
    m.save_service(svc);
    let mut step = service_step();
    step.profile = "test".into();
    step.worktree = "alt".into();
    m.save_workflow(workflow(vec![vec![step]]));
    let stored = read_config_file(dir.join("config.json").to_str().unwrap()).unwrap();
    assert_eq!(stored.workflows[0].stages[0].steps[0].worktree, "alt");
    m.start_workflow("wf");
    wait("固定配置的工作流完成", || {
        flow(&m).state == FlowState::Done
    });
    assert_eq!(service(&m).profile, "test");
    assert_eq!(service(&m).worktree, "alt");
    assert_eq!(m.config().services[0].profile, DEFAULT_PROFILE);
    assert_eq!(m.config().services[0].worktree, DEFAULT_WORKTREE);
    m.save_workflow(workflow(vec![vec![service_step()]]));
    m.start_workflow("wf");
    wait("跟随当前选择的工作流完成", || {
        flow(&m).state == FlowState::Done && service(&m).worktree == DEFAULT_WORKTREE
    });
    assert_eq!(service(&m).profile, DEFAULT_PROFILE);
    let first = service(&m).pid;
    let mut step = service_step();
    step.worktree = "removed".into();
    m.save_workflow(workflow(vec![vec![step]]));
    m.start_workflow("wf");
    assert_eq!(service(&m).pid, first);
    assert!(m
        .logs()
        .iter()
        .any(|l| l.lvl == "ERROR" && l.txt.contains("目录")));
    cleanup(&m, &dir);
}

#[test]
fn following_commands_require_one_directory_for_the_referenced_service() {
    let (m, dir, _) = setup("ambiguous-directory", "exec sleep 918410");
    let mut alt = service_step();
    alt.id = "alt-step".into();
    alt.worktree = "alt".into();
    let prep = Step {
        id: "prep".into(),
        kind: StepKind::Command,
        cwd_service: "web".into(),
        cmd: "touch prepared".into(),
        seconds: 10,
        ..Default::default()
    };
    m.save_workflow(workflow(vec![vec![prep], vec![service_step()], vec![alt]]));
    m.start_workflow("wf");
    assert_eq!(flow(&m).state, FlowState::Failed);
    assert!(flow(&m).message.contains("多个目录"));
    assert!(!m.is_running("web"));
    assert!(!dir.join("main/prepared").exists());
    cleanup(&m, &dir);
}

#[test]
fn stop_and_restart_use_the_original_directory_commands_and_environment() {
    let (m, dir, mut svc) = setup(
        "snapshot",
        "echo $$ > service.pid; echo marker=$HESTIA_TEST; exec sleep 918402",
    );
    svc.stop = "pwd > stopped; kill $(cat service.pid)".into();
    svc.env = vec![EnvVar {
        k: "HESTIA_TEST".into(),
        v: "original".into(),
    }];
    m.save_service(svc.clone());
    m.start_in("web", None, Some("alt"));
    wait("进程已输出", || {
        m.logs().iter().any(|l| l.txt == "marker=original")
    });
    let first = service(&m).pid;
    svc.worktree = DEFAULT_WORKTREE.into();
    svc.cmd = "exit 44".into();
    svc.stop = "touch wrong-stop".into();
    svc.env.clear();
    svc.worktrees.retain(|w| w.id != "alt");
    m.save_service(svc);
    m.restart("web");
    wait("原配置重启", || {
        let s = service(&m);
        s.pid != 0 && s.pid != first
    });
    assert_eq!(service(&m).worktree, "alt");
    assert_eq!(service(&m).cwd, dir.join("alt").display().to_string());
    assert_eq!(
        std::fs::read_to_string(dir.join("alt/stopped"))
            .unwrap()
            .trim(),
        dir.join("alt").display().to_string()
    );
    assert!(!dir.join("main/wrong-stop").exists());
    cleanup(&m, &dir);
}

#[test]
fn automatic_restart_keeps_the_launch_directory_after_configuration_changes() {
    let (m, dir, mut svc) = setup(
        "auto",
        "if [ ! -f crashed ]; then touch crashed; sleep 0.3; exit 3; fi; pwd; exec sleep 918403",
    );
    svc.auto_restart = true;
    m.save_service(svc.clone());
    m.start_in("web", None, Some("alt"));
    wait("首次进程开始", || dir.join("alt/crashed").exists());
    svc.worktree = DEFAULT_WORKTREE.into();
    svc.cmd = "exit 44".into();
    m.save_service(svc);
    wait("自动重启成功", || {
        service(&m).state == RunState::Running && service(&m).restarts > 0
    });
    assert_eq!(service(&m).cwd, dir.join("alt").display().to_string());
    assert!(!dir.join("main/crashed").exists());
    cleanup(&m, &dir);
}

#[test]
fn workflow_selection_and_following_commands_are_frozen_for_the_entire_run() {
    let (m, dir, mut svc) = setup("flow", "pwd; exec sleep 918404");
    let prep = Step {
        id: "prep".into(),
        kind: StepKind::Command,
        cwd_service: "web".into(),
        cmd: "pwd > prepared; sleep 1".into(),
        seconds: 10,
        ..Default::default()
    };
    let mut step = service_step();
    step.worktree = "alt".into();
    m.save_workflow(workflow(vec![vec![prep], vec![step]]));
    m.start_workflow("wf");
    wait("准备命令开始", || dir.join("alt/prepared").exists());
    svc.worktrees.retain(|w| w.id != "alt");
    m.save_service(svc);
    m.save_workflow(workflow(vec![vec![service_step()]]));
    wait("工作流完成", || flow(&m).state == FlowState::Done);
    assert_eq!(service(&m).cwd, dir.join("alt").display().to_string());
    assert_eq!(m.config().services[0].worktree, DEFAULT_WORKTREE);
    assert_eq!(
        std::fs::read_to_string(dir.join("alt/prepared"))
            .unwrap()
            .trim(),
        dir.join("alt").display().to_string()
    );
    assert_eq!(flow(&m).steps[0].cwd, dir.join("alt").display().to_string());
    assert_eq!(flow(&m).matched, 1);
    m.start_in("web", None, Some(DEFAULT_WORKTREE));
    wait("手动切回默认目录", || {
        service(&m).worktree == DEFAULT_WORKTREE
    });
    assert_eq!(flow(&m).matched, 0);
    m.stop_workflow("wf");
    wait("旧工作流停止", || {
        flow(&m).state == FlowState::Stopped
    });
    std::thread::sleep(Duration::from_millis(400));
    assert!(m.is_running("web"), "停止旧工作流不能停止另一目录中的服务");
    cleanup(&m, &dir);
}

#[test]
fn rerunning_the_same_workflow_in_another_directory_replaces_its_run() {
    let (m, dir, _) = setup("rerun", "pwd; exec sleep 918405");
    m.save_workflow(workflow(vec![vec![service_step()]]));
    m.start_workflow("wf");
    wait("首次完成", || flow(&m).state == FlowState::Done);
    let first = service(&m).pid;
    let mut step = service_step();
    step.worktree = "alt".into();
    m.save_workflow(workflow(vec![vec![step]]));
    m.start_workflow("wf");
    wait("新目录的工作流完成", || {
        service(&m).worktree == "alt" && flow(&m).state == FlowState::Done
    });
    assert_ne!(service(&m).pid, first);
    assert_eq!(flow(&m).matched, 1);
    assert_eq!(flow(&m).steps[0].worktree, "alt");
    m.stop_workflow("wf");
    wait("工作流的服务停止", || !m.is_running("web"));
    cleanup(&m, &dir);
}

#[test]
fn concurrent_starts_only_create_one_process_for_the_same_target() {
    let (m, dir, _) = setup("concurrent", "echo $$ >> starts; exec sleep 918406");
    let threads: Vec<_> = (0..8)
        .map(|_| {
            let m = m.clone();
            std::thread::spawn(move || m.start_in("web", None, Some("alt")))
        })
        .collect();
    for thread in threads {
        thread.join().unwrap();
    }
    wait("启动记录已写入", || dir.join("alt/starts").exists());
    assert_eq!(
        std::fs::read_to_string(dir.join("alt/starts"))
            .unwrap()
            .lines()
            .count(),
        1
    );
    cleanup(&m, &dir);
}

#[test]
fn an_old_workflow_does_not_report_or_clear_a_crash_in_another_directory() {
    let (m, dir, mut svc) = setup("other-crash", "exec sleep 918407");
    m.save_workflow(workflow(vec![vec![service_step()]]));
    m.start_workflow("wf");
    wait("工作流完成", || flow(&m).state == FlowState::Done);
    svc.cmd = "exit 7".into();
    m.save_service(svc);
    m.start_in("web", None, Some("alt"));
    wait("另一目录进程退出", || {
        service(&m).state == RunState::Error
    });
    assert_eq!(flow(&m).steps[0].state, StepState::Stopped);
    m.stop_workflow("wf");
    std::thread::sleep(Duration::from_millis(400));
    assert_eq!(service(&m).state, RunState::Error);
    cleanup(&m, &dir);
}
