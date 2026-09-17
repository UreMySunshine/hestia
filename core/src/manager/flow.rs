//! 工作流：阶段按顺序执行，同一阶段内的步骤同时开始，全部完成后进入下一阶段。
//!
//! 服务步骤只决定这次用哪个方案启动，不改服务的当前方案。
//! 某一步失败时不再执行后续阶段，已经启动的服务保持运行。
//! 停止工作流时取消未完成的步骤，并按阶段倒序停掉按工作流方案运行的服务，
//! 其它已启动且未停止的工作流正在用的服务除外。
//!
//! 服务步骤的状态由服务此刻的进程推出，见 [`present`]；运行记录只提供等待中、失败与耗时。

use super::*;

/// 检查就绪状态的间隔
const POLL: Duration = Duration::from_millis(250);
/// 等端口时两次 lsof 的间隔
const PORT_POLL: Duration = Duration::from_secs(1);
/// 取消命令步骤时，SIGTERM 之后等这么久再发 SIGKILL
const KILL_GRACE: Duration = Duration::from_secs(3);
/// 运行记录保留的条数
const EVENT_CAP: usize = 100;

pub(super) struct FlowRun {
    state: FlowState,
    stage: usize,
    started: Instant,
    started_ms: u64,
    finished: Option<Instant>,
    steps: HashMap<String, StepRun>,
    message: String,
    events: Vec<FlowEvent>,
    /// 每次运行一个新的标志，旧运行的线程凭它认出自己已被取代
    cancel: Arc<AtomicBool>,
    /// 执行中的命令步骤：步骤 id → (进程组, 命令)
    commands: HashMap<String, (i32, String)>,
}

impl FlowRun {
    fn event(&mut self, kind: &str, text: String) {
        self.events.push(FlowEvent {
            ts: now_ms(),
            kind: kind.to_string(),
            text,
        });
        if self.events.len() > EVENT_CAP {
            let extra = self.events.len() - EVENT_CAP;
            self.events.drain(..extra);
        }
    }

    fn finish(&mut self, state: FlowState) {
        self.state = state;
        self.finished = Some(Instant::now());
    }

    /// 把还没结束的步骤标为未执行
    fn skip_unfinished(&mut self, why: &str) {
        for s in self.steps.values_mut() {
            if matches!(s.state, StepState::Pending | StepState::Running) {
                s.state = StepState::Skipped;
                s.detail = why.to_string();
                if s.started.is_some() {
                    s.finished = Some(Instant::now());
                }
            }
        }
    }
}

struct StepRun {
    state: StepState,
    detail: String,
    started: Option<Instant>,
    finished: Option<Instant>,
}

impl StepRun {
    fn pending() -> Self {
        Self {
            state: StepState::Pending,
            detail: String::new(),
            started: None,
            finished: None,
        }
    }

    fn status(&self, id: &str) -> StepStatus {
        let elapsed = match self.started {
            Some(s) => self.finished.unwrap_or_else(Instant::now).duration_since(s).as_secs_f64(),
            None => 0.0,
        };
        StepStatus {
            id: id.to_string(),
            state: self.state,
            detail: self.detail.clone(),
            elapsed,
        }
    }
}

enum Outcome {
    Done(String),
    Failed(String),
    Cancelled,
}

/// 服务步骤要求的方案。空串跟随服务的当前方案
fn target_profile(step: &Step, svc: &ServiceConfig) -> String {
    let want = if step.profile.is_empty() { &svc.profile } else { &step.profile };
    svc.launch(want).profile
}

fn service_steps(wf: &Workflow) -> impl Iterator<Item = &Step> {
    wf.stages
        .iter()
        .flat_map(|s| &s.steps)
        .filter(|s| s.kind == StepKind::Service)
}

/// 已启动且未停止：进行中、已完成或失败。只有这样的工作流算作在使用服务
fn started(run: &FlowRun) -> bool {
    matches!(run.state, FlowState::Running | FlowState::Done | FlowState::Failed)
}

/// 工作流里正按其方案运行的服务
fn matched_services<'a>(
    wf: &'a Workflow,
    services: &[ServiceConfig],
    running: &HashMap<String, String>,
) -> HashSet<&'a str> {
    service_steps(wf)
        .filter(|step| {
            services
                .iter()
                .find(|s| s.id == step.service)
                .is_some_and(|svc| running.get(&svc.id) == Some(&target_profile(step, svc)))
        })
        .map(|step| step.service.as_str())
        .collect()
}

/// 服务步骤按服务此刻的进程显示：正按这一步的方案运行为完成，
/// 执行过而此刻异常退出为失败，执行过而此刻已停止或换了方案为已停止，其余照运行记录。
/// 等待就绪中的步骤，以及工作流未被停止时的失败，保留运行记录
fn present(
    status: &mut StepStatus,
    step: &Step,
    stopped: bool,
    services: &[ServiceConfig],
    running: &HashMap<String, String>,
    errored: &HashSet<String>,
) {
    let Some(svc) = services.iter().find(|s| s.id == step.service) else { return };
    match status.state {
        StepState::Running => return,
        StepState::Failed if !stopped => return,
        _ => {}
    }
    let (state, why) = match running.get(&svc.id) {
        Some(p) if *p == target_profile(step, svc) => {
            // 耗时只属于本次运行完成的步骤
            if status.state != StepState::Done {
                *status = StepStatus {
                    id: status.id.clone(),
                    state: StepState::Done,
                    detail: String::new(),
                    elapsed: 0.0,
                };
            }
            return;
        }
        Some(_) => (StepState::Stopped, "已改用其它方案"),
        None if errored.contains(&svc.id) => (StepState::Failed, "异常退出"),
        None => (StepState::Stopped, "已停止"),
    };
    if matches!(status.state, StepState::Done | StepState::Failed) {
        status.state = state;
        status.detail = why.to_string();
    }
}

impl Manager {
    fn flow_changed(&self) {
        (self.emit)("workflows-changed", "null".into());
    }

    /// 以工作流 id 为来源写一条「[工作流名] 」开头的记录，首页的最近活动据此列出
    fn flow_log(&self, wf: &Workflow, lvl: &str, text: &str) {
        self.log(&wf.id, lvl, format!("[{}] {text}", wf.name));
    }

    fn workflow(&self, id: &str) -> Option<Workflow> {
        self.cfg
            .lock()
            .unwrap()
            .workflows
            .iter()
            .find(|w| w.id == id)
            .cloned()
    }

    /// 只在运行记录仍属于这次运行时修改它
    fn with_run(&self, id: &str, cancel: &Arc<AtomicBool>, f: impl FnOnce(&mut FlowRun)) {
        let mut flows = self.flows.lock().unwrap();
        if let Some(r) = flows.get_mut(id) {
            if Arc::ptr_eq(&r.cancel, cancel) {
                f(r);
            }
        }
    }

    fn step_label(&self, step: &Step) -> String {
        match step.kind {
            StepKind::Command => {
                if step.name.trim().is_empty() {
                    step.cmd.clone()
                } else {
                    step.name.clone()
                }
            }
            StepKind::Service => match self.find(&step.service) {
                Some(svc) => {
                    let l = svc.launch(&target_profile(step, &svc));
                    if l.name.is_empty() {
                        svc.name
                    } else {
                        format!("{}（{}）", svc.name, l.name)
                    }
                }
                None => "已删除的服务".to_string(),
            },
        }
    }

    pub fn save_workflow(&self, wf: Workflow) {
        {
            let mut cfg = self.cfg.lock().unwrap();
            match cfg.workflows.iter_mut().find(|w| w.id == wf.id) {
                Some(slot) => *slot = wf,
                None => cfg.workflows.push(wf),
            }
        }
        self.persist();
        self.changed();
    }

    /// 删除工作流。正在执行的步骤会被取消，已启动的服务不动
    pub fn delete_workflow(&self, id: &str) {
        let run = self.flows.lock().unwrap().remove(id);
        if let Some(r) = run {
            r.cancel.store(true, Ordering::SeqCst);
            for (g, _) in r.commands.values() {
                unsafe { libc::kill(-g, libc::SIGTERM) };
            }
        }
        self.cfg.lock().unwrap().workflows.retain(|w| w.id != id);
        self.persist();
        self.changed();
    }

    pub fn start_workflow(self: &Arc<Self>, id: &str) {
        let Some(wf) = self.workflow(id) else { return };
        let cancel = Arc::new(AtomicBool::new(false));
        {
            let mut flows = self.flows.lock().unwrap();
            if flows.get(id).is_some_and(|r| r.state == FlowState::Running) {
                return;
            }
            let steps = wf
                .stages
                .iter()
                .flat_map(|s| &s.steps)
                .map(|s| (s.id.clone(), StepRun::pending()))
                .collect();
            let mut run = FlowRun {
                state: FlowState::Running,
                stage: 0,
                started: Instant::now(),
                started_ms: now_ms(),
                finished: None,
                steps,
                message: String::new(),
                events: Vec::new(),
                cancel: cancel.clone(),
                commands: HashMap::new(),
            };
            run.event("start", "开始运行".into());
            flows.insert(id.to_string(), run);
        }
        self.flow_log(&wf, "INFO", "工作流开始运行");
        self.flow_changed();
        let m = self.clone();
        thread::spawn(move || m.run_flow(wf, cancel));
    }

    /// 取消未完成的步骤，再按阶段倒序停掉按本工作流方案运行的服务，并把异常退出的服务清回已停止。
    /// 其它已启动且未停止的工作流正在用的服务不停
    pub fn stop_workflow(self: &Arc<Self>, id: &str) {
        let Some(wf) = self.workflow(id) else { return };
        let (commands, run): (Vec<i32>, Option<Arc<AtomicBool>>) = {
            let mut flows = self.flows.lock().unwrap();
            match flows.get_mut(id) {
                Some(r) => {
                    r.cancel.store(true, Ordering::SeqCst);
                    if r.state == FlowState::Running {
                        r.skip_unfinished("已停止");
                        r.finish(FlowState::Stopped);
                    } else {
                        r.state = FlowState::Stopped;
                    }
                    r.event("info", "已停止".into());
                    (r.commands.values().map(|(g, _)| *g).collect(), Some(r.cancel.clone()))
                }
                None => (Vec::new(), None),
            }
        };
        for g in commands {
            unsafe { libc::kill(-g, libc::SIGTERM) };
        }
        self.flow_log(&wf, "INFO", "工作流已停止");
        self.flow_changed();

        let m = self.clone();
        thread::spawn(move || {
            let cfg = m.config();
            let others = m.started_flows(&cfg, &wf.id);
            let name = |sid: &str| {
                cfg.services
                    .iter()
                    .find(|s| s.id == sid)
                    .map_or_else(|| sid.to_string(), |s| s.name.clone())
            };

            let mut seen = HashSet::new();
            for stage in wf.stages.iter().rev() {
                let mut notes = Vec::new();
                let mut ids: Vec<String> = Vec::new();
                for step in stage.steps.iter().filter(|s| s.kind == StepKind::Service) {
                    if !seen.insert(step.service.clone()) {
                        continue;
                    }
                    if !m.step_matched(step) {
                        if m.errored(&step.service) {
                            ids.push(step.service.clone());
                        }
                        continue;
                    }
                    let user = others.iter().find(|o| {
                        service_steps(o).any(|s| s.service == step.service && m.step_matched(s))
                    });
                    match user {
                        Some(o) => {
                            let who = name(&step.service);
                            notes.push(format!("{who} 仍被「{}」使用，未停止", o.name));
                        }
                        None => ids.push(step.service.clone()),
                    }
                }
                for id in &ids {
                    m.stop(id);
                }
                for id in &ids {
                    let text = if m.wait_gone(id, Duration::from_secs(16)) {
                        "已停止"
                    } else {
                        "未能在 16 秒内停止"
                    };
                    notes.push(format!("{} {text}", name(id)));
                }

                if let Some(run) = &run {
                    m.with_run(&wf.id, run, |r| {
                        for text in notes {
                            r.event("info", text);
                        }
                    });
                }
                m.flow_changed();
            }
        });
    }

    /// 除 `except` 外已启动且未停止的工作流
    fn started_flows(&self, cfg: &AppConfig, except: &str) -> Vec<Workflow> {
        let flows = self.flows.lock().unwrap();
        cfg.workflows
            .iter()
            .filter(|o| o.id != except && flows.get(&o.id).is_some_and(started))
            .cloned()
            .collect()
    }

    fn errored(&self, id: &str) -> bool {
        self.procs
            .lock()
            .unwrap()
            .get(id)
            .is_some_and(|p| p.state == RunState::Error)
    }

    /// 运行中的服务 → 所用方案
    fn running_profiles(&self) -> HashMap<String, String> {
        self.procs
            .lock()
            .unwrap()
            .iter()
            .filter(|(_, p)| p.state == RunState::Running)
            .map(|(id, p)| (id.clone(), p.profile.clone()))
            .collect()
    }

    /// 服务是否正按这一步要求的方案运行
    fn step_matched(&self, step: &Step) -> bool {
        let Some(svc) = self.find(&step.service) else { return false };
        self.running_profile(&step.service) == Some(target_profile(step, &svc))
    }

    /// 取消所有运行中的工作流，返回执行中命令的进程组。退出前调用
    pub(super) fn cancel_flows(&self) -> Vec<i32> {
        let flows = self.flows.lock().unwrap();
        let mut out = Vec::new();
        for r in flows.values() {
            r.cancel.store(true, Ordering::SeqCst);
            out.extend(r.commands.values().map(|(g, _)| *g));
        }
        out
    }

    /// 执行中的命令步骤，与服务进程一起写入 running.json
    pub(super) fn flow_commands(&self) -> Vec<RunningEntry> {
        self.flows
            .lock()
            .unwrap()
            .values()
            .flat_map(|r| &r.commands)
            .map(|(id, (g, cmd))| RunningEntry {
                id: id.clone(),
                pid: *g as u32,
                pgid: *g,
                cmd: cmd.clone(),
            })
            .collect()
    }

    pub(super) fn flow_statuses(&self, cfg: &AppConfig) -> Vec<WorkflowStatus> {
        let running = self.running_profiles();
        let errored: HashSet<String> = self
            .procs
            .lock()
            .unwrap()
            .iter()
            .filter(|(_, p)| p.state == RunState::Error)
            .map(|(id, _)| id.clone())
            .collect();
        let flows = self.flows.lock().unwrap();

        cfg.workflows
            .iter()
            .map(|wf| {
                let members: HashSet<&str> = service_steps(wf)
                    .filter(|s| cfg.services.iter().any(|x| x.id == s.service))
                    .map(|s| s.service.as_str())
                    .collect();
                let matched = matched_services(wf, &cfg.services, &running).len();
                let run = flows.get(&wf.id);
                let stopped = run.is_some_and(|r| r.state == FlowState::Stopped);
                let steps = wf
                    .stages
                    .iter()
                    .flat_map(|s| &s.steps)
                    .map(|s| {
                        let mut status = match run.and_then(|r| r.steps.get(&s.id)) {
                            Some(x) => x.status(&s.id),
                            None => StepRun::pending().status(&s.id),
                        };
                        if s.kind == StepKind::Service {
                            present(&mut status, s, stopped, &cfg.services, &running, &errored);
                        }
                        status
                    })
                    .collect();

                WorkflowStatus {
                    id: wf.id.clone(),
                    state: run.map(|r| r.state).unwrap_or(FlowState::Idle),
                    stage: run.map(|r| r.stage).unwrap_or(0),
                    started: run.map(|r| r.started_ms).unwrap_or(0),
                    elapsed: run
                        .map(|r| {
                            r.finished
                                .unwrap_or_else(Instant::now)
                                .duration_since(r.started)
                                .as_secs_f64()
                        })
                        .unwrap_or(0.0),
                    steps,
                    message: run.map(|r| r.message.clone()).unwrap_or_default(),
                    events: run.map(|r| r.events.clone()).unwrap_or_default(),
                    members: members.len(),
                    matched,
                }
            })
            .collect()
    }

    fn run_flow(self: &Arc<Self>, wf: Workflow, cancel: Arc<AtomicBool>) {
        for (i, stage) in wf.stages.iter().enumerate() {
            if cancel.load(Ordering::SeqCst) {
                return;
            }
            let labels: Vec<String> = stage.steps.iter().map(|s| self.step_label(s)).collect();
            self.with_run(&wf.id, &cancel, |r| {
                r.stage = i;
                r.event("info", format!("阶段 {}：{}", i + 1, labels.join("、")));
            });
            self.flow_changed();

            let handles: Vec<_> = stage
                .steps
                .iter()
                .cloned()
                .map(|step| {
                    let m = self.clone();
                    let wf_id = wf.id.clone();
                    let cancel = cancel.clone();
                    thread::spawn(move || m.run_step(&wf_id, &step, &cancel))
                })
                .collect();

            // 同一阶段的步骤全部结束才汇总，失败的那一步不打断其它步骤
            let mut failed = false;
            for h in handles {
                if matches!(h.join(), Ok(Outcome::Failed(_)) | Err(_)) {
                    failed = true;
                }
            }
            if cancel.load(Ordering::SeqCst) {
                return;
            }
            if failed {
                let mut summary = None;
                self.with_run(&wf.id, &cancel, |r| {
                    let reasons: Vec<String> = stage
                        .steps
                        .iter()
                        .filter_map(|s| r.steps.get(&s.id).map(|x| (s, x)))
                        .filter(|(_, x)| x.state == StepState::Failed)
                        .map(|(s, x)| format!("{} {}", labels_of(stage, &labels, &s.id), x.detail))
                        .collect();
                    r.message = reasons.join("；");
                    r.skip_unfinished("前一阶段失败，已跳过");
                    r.finish(FlowState::Failed);
                    let tail = if i + 1 < wf.stages.len() { "，后续阶段未执行" } else { "" };
                    r.event("error", format!("阶段 {} 失败{tail}", i + 1));
                    summary = Some(format!("工作流在阶段 {} 失败：{}", i + 1, r.message));
                });
                if let Some(text) = summary {
                    self.flow_log(&wf, "ERROR", &text);
                }
                self.flow_changed();
                return;
            }
            self.with_run(&wf.id, &cancel, |r| {
                r.event("done", format!("阶段 {} 完成", i + 1));
            });
            self.flow_changed();
        }
        let mut finished = false;
        self.with_run(&wf.id, &cancel, |r| {
            r.finish(FlowState::Done);
            r.event("done", "全部就绪".into());
            finished = true;
        });
        if finished {
            self.flow_log(&wf, "INFO", "工作流全部就绪");
        }
        self.flow_changed();
    }

    fn run_step(self: &Arc<Self>, wf_id: &str, step: &Step, cancel: &Arc<AtomicBool>) -> Outcome {
        let label = self.step_label(step);
        self.with_run(wf_id, cancel, |r| {
            let s = r.steps.entry(step.id.clone()).or_insert_with(StepRun::pending);
            s.state = StepState::Running;
            s.started = Some(Instant::now());
        });
        self.flow_changed();

        let out = match step.kind {
            StepKind::Service => self.run_service_step(step, cancel),
            StepKind::Command => self.run_command_step(wf_id, step, cancel),
        };

        self.with_run(wf_id, cancel, |r| {
            let (state, detail) = match &out {
                Outcome::Done(d) => (StepState::Done, d.clone()),
                Outcome::Failed(d) => (StepState::Failed, d.clone()),
                Outcome::Cancelled => (StepState::Skipped, "已停止".to_string()),
            };
            if let Some(s) = r.steps.get_mut(&step.id) {
                s.state = state;
                s.detail = detail.clone();
                s.finished = Some(Instant::now());
            }
            match &out {
                Outcome::Done(_) => r.event("info", format!("{label} {detail}")),
                Outcome::Failed(_) => r.event("error", format!("{label} {detail}")),
                Outcome::Cancelled => {}
            }
        });
        self.flow_changed();
        out
    }

    fn run_service_step(self: &Arc<Self>, step: &Step, cancel: &AtomicBool) -> Outcome {
        let Some(svc) = self.find(&step.service) else {
            return Outcome::Failed("服务已删除".into());
        };
        // 只决定这次用哪个方案启动，不改服务的当前方案
        let target = target_profile(step, &svc);

        let already = match self.running_profile(&svc.id) {
            Some(cur) if cur == target => true,
            Some(_) => {
                if !self.switch(&svc.id, &target) {
                    return Outcome::Failed(self.start_failure(&svc.id));
                }
                false
            }
            None => {
                if !self.spawn_as(&svc.id, &target) {
                    return Outcome::Failed(self.start_failure(&svc.id));
                }
                false
            }
        };
        // 登记停止之前刚拉起的进程不在停止的名单里，这里自己收掉
        if !already && cancel.load(Ordering::SeqCst) {
            self.stop(&svc.id);
            return Outcome::Cancelled;
        }

        let Some((generation, pid, started)) = self.proc_ident(&svc.id) else {
            return Outcome::Failed(self.start_failure(&svc.id));
        };
        let out = match step.ready {
            ReadyKind::Port => {
                self.wait_port(&svc.id, generation, pid, step.seconds.max(1), cancel)
            }
            ReadyKind::Delay => {
                self.wait_delay(&svc.id, generation, started, step.seconds, cancel)
            }
        };
        match out {
            Outcome::Done(d) if already => match step.ready {
                ReadyKind::Port => Outcome::Done(format!("已在运行 · {d}")),
                ReadyKind::Delay => Outcome::Done("已在运行".into()),
            },
            other => other,
        }
    }

    fn start_failure(&self, id: &str) -> String {
        let procs = self.procs.lock().unwrap();
        match procs.get(id) {
            Some(p) if p.state == RunState::Running => "旧进程未能及时停止，无法切换方案".into(),
            Some(p) if !p.last_error.is_empty() => p.last_error.clone(),
            _ => "启动失败".into(),
        }
    }

    /// 运行中进程的代次、pid 与启动时刻
    fn proc_ident(&self, id: &str) -> Option<(u64, u32, Instant)> {
        self.procs
            .lock()
            .unwrap()
            .get(id)
            .filter(|p| p.state == RunState::Running && p.pid != 0)
            .map(|p| (p.generation, p.pid, p.started))
    }

    /// 这一代进程是否还在运行；不在时返回原因
    fn still_up(&self, id: &str, generation: u64) -> Result<(), String> {
        let procs = self.procs.lock().unwrap();
        match procs.get(id) {
            Some(p) if p.generation == generation => match p.state {
                RunState::Running => Ok(()),
                RunState::Error => Err(format!("就绪前退出（{}）", p.last_error)),
                RunState::Stopped => Err("就绪前被停止".into()),
            },
            _ => Err("就绪前退出，已被自动重启".into()),
        }
    }

    fn wait_port(
        &self,
        id: &str,
        generation: u64,
        pid: u32,
        timeout: u64,
        cancel: &AtomicBool,
    ) -> Outcome {
        let deadline = Instant::now() + Duration::from_secs(timeout);
        let mut next_scan = Instant::now();
        loop {
            if cancel.load(Ordering::SeqCst) {
                return Outcome::Cancelled;
            }
            if let Err(why) = self.still_up(id, generation) {
                return Outcome::Failed(why);
            }
            if Instant::now() >= next_scan {
                let pids: Vec<u32> = tree_pids(pid).iter().map(|p| p.as_u32()).collect();
                let mut ports: Vec<u16> = listening_ports(&pids).into_values().flatten().collect();
                ports.sort_unstable();
                ports.dedup();
                if !ports.is_empty() {
                    // 探测窗口过后快照不再扫描，这里的结果直接写进缓存供界面显示
                    self.ports
                        .lock()
                        .unwrap()
                        .insert(id.to_string(), (generation, ports.clone()));
                    let list: Vec<String> = ports.iter().map(|p| p.to_string()).collect();
                    return Outcome::Done(format!("端口 {}", list.join("、")));
                }
                next_scan = Instant::now() + PORT_POLL;
            }
            if Instant::now() >= deadline {
                return Outcome::Failed(format!("{timeout} 秒内未监听端口"));
            }
            thread::sleep(POLL);
        }
    }

    fn wait_delay(
        &self,
        id: &str,
        generation: u64,
        started: Instant,
        seconds: u64,
        cancel: &AtomicBool,
    ) -> Outcome {
        let until = started + Duration::from_secs(seconds);
        loop {
            if cancel.load(Ordering::SeqCst) {
                return Outcome::Cancelled;
            }
            if let Err(why) = self.still_up(id, generation) {
                return Outcome::Failed(why);
            }
            let now = Instant::now();
            if now >= until {
                return Outcome::Done(format!("已等待 {seconds} 秒"));
            }
            thread::sleep(POLL.min(until - now));
        }
    }

    fn run_command_step(self: &Arc<Self>, wf_id: &str, step: &Step, cancel: &Arc<AtomicBool>) -> Outcome {
        if step.cmd.trim().is_empty() {
            return Outcome::Failed("未填写命令".into());
        }
        let cwd = expand_home(&step.cwd);
        if !step.cwd.trim().is_empty() && !cwd.is_dir() {
            return Outcome::Failed(format!("工作目录不存在：{}", cwd.display()));
        }

        let shell = std::env::var("SHELL").unwrap_or_else(|_| "/bin/sh".into());
        let mut c = Command::new(shell);
        c.arg("-lc").arg(&step.cmd);
        if !step.cwd.trim().is_empty() {
            c.current_dir(&cwd);
        }
        c.stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        unsafe {
            c.pre_exec(|| {
                libc::setsid();
                Ok(())
            });
        }
        let mut child = match c.spawn() {
            Ok(ch) => ch,
            Err(e) => return Outcome::Failed(format!("启动失败：{e}")),
        };
        let pgid = child.id() as i32;
        reaper::track(pgid);
        self.with_run(wf_id, cancel, |r| {
            r.commands.insert(step.id.clone(), (pgid, step.cmd.clone()));
        });
        self.persist_running();

        // 输出以步骤 id 作为来源，工作流页据此筛出这一步的输出
        if let Some(out) = child.stdout.take() {
            self.pump(step.id.clone(), out);
        }
        if let Some(err) = child.stderr.take() {
            self.pump(step.id.clone(), err);
        }

        let seconds = step.seconds.max(1);
        let deadline = Instant::now() + Duration::from_secs(seconds);
        let mut signalled: Option<Instant> = None;
        let mut timed_out = false;
        let out = loop {
            match child.try_wait() {
                Ok(Some(status)) => {
                    break match status.code() {
                        _ if timed_out => Outcome::Failed(format!("超过 {seconds} 秒未结束")),
                        _ if cancel.load(Ordering::SeqCst) => Outcome::Cancelled,
                        Some(0) => Outcome::Done("退出码 0".into()),
                        Some(code) => Outcome::Failed(format!("退出码 {code}")),
                        None => Outcome::Failed("被信号终止".into()),
                    };
                }
                Ok(None) => {}
                Err(e) => break Outcome::Failed(format!("等待进程失败：{e}")),
            }
            if signalled.is_none() {
                if Instant::now() >= deadline {
                    timed_out = true;
                }
                if timed_out || cancel.load(Ordering::SeqCst) {
                    unsafe { libc::kill(-pgid, libc::SIGTERM) };
                    signalled = Some(Instant::now());
                }
            } else if signalled.is_some_and(|t| t.elapsed() >= KILL_GRACE) {
                unsafe { libc::kill(-pgid, libc::SIGKILL) };
            }
            thread::sleep(POLL);
        };

        reaper::untrack(pgid);
        self.with_run(wf_id, cancel, |r| {
            r.commands.remove(&step.id);
        });
        self.persist_running();
        out
    }
}

/// 某一步在本阶段标签列表里的名字
fn labels_of<'a>(stage: &Stage, labels: &'a [String], step_id: &str) -> &'a str {
    stage
        .steps
        .iter()
        .position(|s| s.id == step_id)
        .and_then(|i| labels.get(i))
        .map(|s| s.as_str())
        .unwrap_or("")
}
