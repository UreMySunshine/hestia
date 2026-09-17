use std::collections::{HashMap, HashSet, VecDeque};
use std::io::{BufRead, BufReader, Read};
use std::os::unix::process::CommandExt;
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use crate::reaper;
use crate::types::*;
use sysinfo::{Pid, ProcessRefreshKind, ProcessesToUpdate, System};

mod flow;

/// 崩溃后自动重启的最大次数
const MAX_RESTARTS: u32 = 5;
/// 两次采样的最小间隔。sysinfo 的 CPU 是两次刷新之间的差值，
/// 间隔太短算出来的值不可信（实测紧邻 50ms 再采一次会读到 4%，而真实值是 101%）。
/// 主窗口和菜单栏窗口各有一个轮询，两者可能撞在一起，所以在这里统一节流。
const MIN_SAMPLE: Duration = Duration::from_millis(400);
/// 端口探测的放弃时限。进程刚起来还没绑端口，需要轮询一小段时间；
/// 一旦探到就不再查，超过这个时限还没有则认定它不监听端口
const PORT_SCAN_WINDOW: Duration = Duration::from_secs(60);

struct Proc {
    pid: u32,
    pgid: i32,
    started: Instant,
    state: RunState,
    restarts: u32,
    errors: u32,
    last_error: String,
    /// 手动停止时置位，退出监视线程据此区分正常停止与崩溃
    stopping: Arc<AtomicBool>,
    /// 每次启动自增，用于丢弃过期的退出通知
    generation: u64,
    /// 本次进程所用的方案
    profile: String,
    /// 本次进程实际执行的命令，写入 running.json 供下次启动核对
    cmd: String,
}

impl Proc {
    fn idle() -> Self {
        Self {
            pid: 0,
            pgid: 0,
            started: Instant::now(),
            state: RunState::Stopped,
            restarts: 0,
            errors: 0,
            last_error: String::new(),
            stopping: Arc::new(AtomicBool::new(false)),
            generation: 0,
            profile: String::new(),
            cmd: String::new(),
        }
    }
}

/// 落盘的运行态，用于下次启动时回收上一轮残留的进程
#[derive(serde::Serialize, serde::Deserialize, Clone, Debug)]
struct RunningEntry {
    id: String,
    pid: u32,
    pgid: i32,
    /// 记录命令用于比对，避免 pid 被复用后误杀无关进程
    cmd: String,
}

/// 事件回调：(事件名, JSON 负载)。界面层据此刷新，核心不关心谁在监听
pub type Emit = Arc<dyn Fn(&str, String) + Send + Sync>;

pub struct Manager {
    emit: Emit,
    cfg_path: PathBuf,
    run_path: PathBuf,
    cfg: Mutex<AppConfig>,
    procs: Mutex<HashMap<String, Proc>>,
    logs: Mutex<VecDeque<LogLine>>,
    /// 日志保留行数，取自偏好设置，写日志时不必去锁配置
    log_cap: AtomicUsize,
    pending: Mutex<Vec<LogLine>>,
    sys: Mutex<System>,
    /// 上一次真正刷新 sysinfo 的时刻，用于给 CPU 差值留出足够间隔
    last_sample: Mutex<Option<Instant>>,
    /// 端口探测结果，按「服务 id → (启动代次, 端口)」缓存。
    /// 端口起来后不会变，因此探到就不再查；进程重启会换代次，届时重新探测
    ports: Mutex<HashMap<String, (u64, Vec<u16>)>>,
    /// 工作流的运行状态，按工作流 id
    flows: Mutex<HashMap<String, flow::FlowRun>>,
    seq: AtomicU64,
    gen: AtomicU64,
    started: Instant,
}

fn clamp_log_lines(n: usize) -> usize {
    n.clamp(LOG_LINES_MIN, LOG_LINES_MAX)
}

/// 删掉引用了不存在服务的步骤，阶段空了一并删掉
fn prune_steps(cfg: &mut AppConfig) {
    let ids: HashSet<String> = cfg.services.iter().map(|s| s.id.clone()).collect();
    for wf in cfg.workflows.iter_mut() {
        for stage in wf.stages.iter_mut() {
            stage
                .steps
                .retain(|s| s.kind != StepKind::Service || ids.contains(&s.service));
        }
        wf.stages.retain(|s| !s.steps.is_empty());
    }
}

/// 读取并校验导入用的配置文件
pub fn read_config_file(path: &str) -> Result<AppConfig, String> {
    let text = std::fs::read_to_string(path).map_err(|e| format!("读取失败：{e}"))?;
    let value: serde_json::Value =
        serde_json::from_str(&text).map_err(|_| "文件不是有效的 JSON".to_string())?;
    // 各字段都有默认值，任意 JSON 对象都能解析，这里要求至少带服务列表
    if !value.get("services").is_some_and(|v| v.is_array()) {
        return Err("文件里没有服务列表，不是 Hestia 的配置文件".into());
    }
    serde_json::from_value(value).map_err(|e| format!("配置格式不正确：{e}"))
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

fn expand_home(p: &str) -> PathBuf {
    let p = p.trim();
    if p == "~" || p.starts_with("~/") {
        if let Some(home) = std::env::var_os("HOME") {
            let mut base = PathBuf::from(home);
            if p.len() > 2 {
                base.push(&p[2..]);
            }
            return base;
        }
    }
    PathBuf::from(p)
}

/// 按行内容判定日志级别，标准输出与标准错误都走同一套规则
fn classify(line: &str) -> &'static str {
    let l = line.to_ascii_lowercase();
    if l.contains("error") || l.contains("panic") || l.contains("fatal") || l.contains("exception")
    {
        "ERROR"
    } else if l.contains("warn") {
        "WARN"
    } else {
        "INFO"
    }
}

impl Manager {
    /// 指定配置目录，便于测试
    pub fn new_in(dir: PathBuf, emit: Emit) -> Arc<Self> {
        let _ = std::fs::create_dir_all(&dir);
        let cfg_path = dir.join("config.json");
        let run_path = dir.join("running.json");
        reap_orphans(&run_path);

        // 配置文件不存在或读不出来就用空配置。首次运行不写入任何示例服务——
        // 示例里的路径指向本机不存在的目录，装到别人机器上会一开就是一片报错。
        // 界面的空状态是可点的引导卡片，不需要示例数据来充场面。
        let cfg = std::fs::read_to_string(&cfg_path)
            .ok()
            .and_then(|s| serde_json::from_str::<AppConfig>(&s).ok())
            .unwrap_or_default();

        let log_cap = clamp_log_lines(cfg.prefs.log_lines);
        let m = Arc::new(Self {
            emit,
            cfg_path,
            run_path,
            cfg: Mutex::new(cfg),
            procs: Mutex::new(HashMap::new()),
            logs: Mutex::new(VecDeque::new()),
            log_cap: AtomicUsize::new(log_cap),
            pending: Mutex::new(Vec::new()),
            sys: Mutex::new(System::new()),
            last_sample: Mutex::new(None),
            ports: Mutex::new(HashMap::new()),
            flows: Mutex::new(HashMap::new()),
            seq: AtomicU64::new(0),
            gen: AtomicU64::new(0),
            started: Instant::now(),
        });
        m.persist();

        // 日志按 200ms 成批推送，避免话痨进程刷爆 IPC
        let flusher = m.clone();
        thread::spawn(move || loop {
            thread::sleep(Duration::from_millis(200));
            let batch: Vec<LogLine> = {
                let mut p = flusher.pending.lock().unwrap();
                if p.is_empty() {
                    continue;
                }
                std::mem::take(&mut *p)
            };
            let json = serde_json::to_string(&batch).unwrap_or_else(|_| "[]".into());
            (flusher.emit)("logs", json);
        });

        m
    }

    // ── 配置 ────────────────────────────────────────────────

    pub fn config(&self) -> AppConfig {
        self.cfg.lock().unwrap().clone()
    }

    fn persist(&self) {
        let cfg = self.cfg.lock().unwrap();
        if let Ok(s) = serde_json::to_string_pretty(&*cfg) {
            let _ = std::fs::write(&self.cfg_path, s);
        }
    }

    /// 把运行中的进程组落盘，供下次启动回收残留
    fn persist_running(&self) {
        let mut list: Vec<RunningEntry> = self
            .procs
            .lock()
            .unwrap()
            .iter()
            .filter(|(_, p)| p.state == RunState::Running && p.pgid > 0)
            .map(|(id, p)| RunningEntry {
                id: id.clone(),
                pid: p.pid,
                pgid: p.pgid,
                cmd: p.cmd.clone(),
            })
            .collect();
        list.extend(self.flow_commands());
        if let Ok(s) = serde_json::to_string_pretty(&list) {
            let _ = std::fs::write(&self.run_path, s);
        }
    }

    fn changed(&self) {
        (self.emit)("services-changed", "null".into());
    }

    fn find(&self, id: &str) -> Option<ServiceConfig> {
        self.cfg
            .lock()
            .unwrap()
            .services
            .iter()
            .find(|s| s.id == id)
            .cloned()
    }

    pub fn save_service(&self, mut svc: ServiceConfig) {
        if !svc.profiles.iter().any(|p| p.id == svc.profile) {
            svc.profile = DEFAULT_PROFILE.to_string();
        }
        {
            let mut cfg = self.cfg.lock().unwrap();
            match cfg.services.iter_mut().find(|s| s.id == svc.id) {
                Some(slot) => *slot = svc,
                None => cfg.services.push(svc),
            }
        }
        self.persist();
        self.changed();
    }

    /// 按给定的 id 顺序重排服务。ids 里没提到的服务保持原有相对次序排在后面，
    /// 这样即使前端拿的是旧列表，也不会把新增的服务弄丢
    pub fn reorder_services(&self, ids: Vec<String>) {
        {
            let mut cfg = self.cfg.lock().unwrap();
            let rank: HashMap<&str, usize> = ids
                .iter()
                .enumerate()
                .map(|(i, id)| (id.as_str(), i))
                .collect();
            cfg.services
                .sort_by_key(|s| rank.get(s.id.as_str()).copied().unwrap_or(usize::MAX));
        }
        self.persist();
        self.changed();
    }

    pub fn delete_service(self: &Arc<Self>, id: String) {
        self.stop(&id);
        {
            let mut cfg = self.cfg.lock().unwrap();
            cfg.services.retain(|s| s.id != id);
            prune_steps(&mut cfg);
        }
        self.procs.lock().unwrap().remove(&id);
        self.persist();
        self.changed();
    }

    pub fn set_prefs(&self, mut prefs: Prefs) {
        prefs.log_lines = clamp_log_lines(prefs.log_lines);
        self.apply_log_cap(prefs.log_lines);
        self.cfg.lock().unwrap().prefs = prefs;
        self.persist();
        self.changed();
    }

    /// 改日志保留行数，调小时立即丢掉最早的行
    fn apply_log_cap(&self, cap: usize) {
        self.log_cap.store(cap, Ordering::Relaxed);
        let mut logs = self.logs.lock().unwrap();
        while logs.len() > cap {
            logs.pop_front();
        }
    }

    /// 把当前配置写到指定文件，格式与配置目录里的 config.json 相同
    pub fn export_config(&self, path: &str) -> Result<(), String> {
        let text = serde_json::to_string_pretty(&self.config()).map_err(|e| e.to_string())?;
        std::fs::write(path, text).map_err(|e| format!("写入失败：{e}"))
    }

    /// 导入配置。合并时同 id 的服务和工作流被覆盖，其余保留，偏好不变；
    /// 替换时以导入内容为准，不在其中的服务先停掉，工作流先取消，偏好里的开机自启保留本机的设置
    pub fn import_config(self: &Arc<Self>, incoming: AppConfig, replace: bool) {
        if replace {
            let (gone_services, gone_flows) = {
                let cfg = self.cfg.lock().unwrap();
                let keep: HashSet<&str> = incoming.services.iter().map(|s| s.id.as_str()).collect();
                let keep_flows: HashSet<&str> =
                    incoming.workflows.iter().map(|w| w.id.as_str()).collect();
                (
                    cfg.services
                        .iter()
                        .filter(|s| !keep.contains(s.id.as_str()))
                        .map(|s| s.id.clone())
                        .collect::<Vec<_>>(),
                    cfg.workflows
                        .iter()
                        .filter(|w| !keep_flows.contains(w.id.as_str()))
                        .map(|w| w.id.clone())
                        .collect::<Vec<_>>(),
                )
            };
            // stop 要读服务配置里的停止命令，必须在移除配置之前调用
            for id in &gone_services {
                self.stop(id);
            }
            for id in &gone_flows {
                self.delete_workflow(id);
            }
        }

        let log_cap = {
            let mut cfg = self.cfg.lock().unwrap();
            if replace {
                let autostart = cfg.prefs.autostart;
                cfg.services = incoming.services;
                cfg.workflows = incoming.workflows;
                cfg.prefs = Prefs { autostart, ..incoming.prefs };
                cfg.prefs.log_lines = clamp_log_lines(cfg.prefs.log_lines);
            } else {
                for svc in incoming.services {
                    match cfg.services.iter_mut().find(|s| s.id == svc.id) {
                        Some(slot) => *slot = svc,
                        None => cfg.services.push(svc),
                    }
                }
                for wf in incoming.workflows {
                    match cfg.workflows.iter_mut().find(|w| w.id == wf.id) {
                        Some(slot) => *slot = wf,
                        None => cfg.workflows.push(wf),
                    }
                }
            }
            prune_steps(&mut cfg);
            cfg.prefs.log_lines
        };
        self.apply_log_cap(log_cap);
        self.persist();
        self.changed();
    }

    // ── 日志 ────────────────────────────────────────────────

    fn log(&self, sid: &str, lvl: &str, txt: String) {
        let line = LogLine {
            id: format!("l{}", self.seq.fetch_add(1, Ordering::Relaxed)),
            ts: now_ms(),
            lvl: lvl.to_string(),
            txt,
            sid: sid.to_string(),
        };
        {
            let cap = self.log_cap.load(Ordering::Relaxed);
            let mut logs = self.logs.lock().unwrap();
            logs.push_back(line.clone());
            while logs.len() > cap {
                logs.pop_front();
            }
        }
        self.pending.lock().unwrap().push(line);
    }

    pub fn logs(&self) -> Vec<LogLine> {
        self.logs.lock().unwrap().iter().cloned().collect()
    }

    pub fn clear_logs(&self) {
        self.logs.lock().unwrap().clear();
    }

    // ── 启停 ────────────────────────────────────────────────

    /// 是否有任何被托管的服务在运行
    pub fn any_running(&self) -> bool {
        self.procs
            .lock()
            .unwrap()
            .values()
            .any(|p| p.state == RunState::Running)
    }

    pub fn is_running(&self, id: &str) -> bool {
        self.procs
            .lock()
            .unwrap()
            .get(id)
            .map(|p| p.state == RunState::Running)
            .unwrap_or(false)
    }

    /// 运行中的进程所用的方案
    fn running_profile(&self, id: &str) -> Option<String> {
        self.procs
            .lock()
            .unwrap()
            .get(id)
            .filter(|p| p.state == RunState::Running)
            .map(|p| p.profile.clone())
    }

    /// 改服务的当前方案
    fn set_profile(&self, id: &str, profile: &str) {
        let changed = {
            let mut cfg = self.cfg.lock().unwrap();
            match cfg.services.iter_mut().find(|s| s.id == id) {
                Some(s) if s.profile != profile => {
                    s.profile = profile.to_string();
                    true
                }
                _ => false,
            }
        };
        if changed {
            self.persist();
            self.changed();
        }
    }

    pub fn start(self: &Arc<Self>, id: &str) {
        self.start_as(id, None);
    }

    /// 按指定方案启动并把它记为当前方案，`None` 按当前方案。
    /// 服务正以别的方案运行时先停止再启动
    pub fn start_as(self: &Arc<Self>, id: &str, profile: Option<&str>) {
        let Some(svc) = self.find(id) else { return };
        let target = svc.launch(profile.unwrap_or(&svc.profile)).profile;
        if profile.is_some() {
            self.set_profile(id, &target);
        }
        match self.running_profile(id) {
            Some(cur) if cur == target => {}
            Some(_) => {
                let m = self.clone();
                let id = id.to_string();
                thread::spawn(move || {
                    m.switch(&id, &target);
                });
            }
            None => {
                self.spawn_as(id, &target);
            }
        }
    }

    /// 停掉当前进程后按新方案启动，返回是否已拉起。会阻塞到旧进程退出
    fn switch(self: &Arc<Self>, id: &str, profile: &str) -> bool {
        if let Some(svc) = self.find(id) {
            let l = svc.launch(profile);
            let label = if l.name.is_empty() { "默认" } else { l.name.as_str() };
            self.log(id, "INFO", format!("[{}] 切换到方案「{label}」", svc.name));
        }
        self.stop(id);
        // 停止命令最多等 8 秒，SIGTERM 再等 5 秒，之后才发 SIGKILL
        self.wait_gone(id, Duration::from_secs(16));
        self.spawn_as(id, profile)
    }

    /// 按方案拉起进程，返回是否已拉起
    fn spawn_as(self: &Arc<Self>, id: &str, profile: &str) -> bool {
        if self.is_running(id) {
            return false;
        }
        let Some(svc) = self.find(id) else { return false };
        let launch = svc.launch(profile);

        let cwd = expand_home(&svc.cwd);
        if !svc.cwd.trim().is_empty() && !cwd.is_dir() {
            self.fail(id, format!("工作目录不存在：{}", cwd.display()));
            return false;
        }
        if launch.cmd.trim().is_empty() {
            self.fail(id, "未配置启动命令".to_string());
            return false;
        }

        let child = match Self::spawn_child(&launch, &svc.cwd, &cwd) {
            Ok(c) => c,
            Err(e) => {
                self.fail(id, format!("启动失败：{e}"));
                return false;
            }
        };
        self.adopt(svc, launch, child);
        true
    }

    fn spawn_child(launch: &Launch, raw_cwd: &str, cwd: &PathBuf) -> std::io::Result<Child> {
        let shell = std::env::var("SHELL").unwrap_or_else(|_| "/bin/sh".into());
        let mut c = Command::new(shell);
        c.arg("-lc").arg(&launch.cmd);
        if !raw_cwd.trim().is_empty() {
            c.current_dir(cwd);
        }
        for e in &launch.env {
            if !e.k.trim().is_empty() {
                c.env(e.k.trim(), &e.v);
            }
        }
        c.stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        // 独立会话，停止时可以整组回收，避免留下孤儿子进程
        unsafe {
            c.pre_exec(|| {
                libc::setsid();
                Ok(())
            });
        }
        c.spawn()
    }

    /// 记录新进程，挂上日志泵与退出监视
    fn adopt(self: &Arc<Self>, svc: ServiceConfig, launch: Launch, mut child: Child) {
        let pid = child.id();
        let generation = self.gen.fetch_add(1, Ordering::Relaxed) + 1;
        let stopping = Arc::new(AtomicBool::new(false));

        {
            let mut procs = self.procs.lock().unwrap();
            let slot = procs.entry(svc.id.clone()).or_insert_with(Proc::idle);
            slot.pid = pid;
            slot.pgid = pid as i32;
            slot.started = Instant::now();
            slot.state = RunState::Running;
            slot.last_error.clear();
            slot.stopping = stopping.clone();
            slot.generation = generation;
            slot.profile = launch.profile.clone();
            slot.cmd = launch.cmd.clone();
        }

        reaper::track(pid as i32);
        self.persist_running();

        if let Some(out) = child.stdout.take() {
            self.pump(svc.id.clone(), out);
        }
        if let Some(err) = child.stderr.take() {
            self.pump(svc.id.clone(), err);
        }

        let msg = if launch.name.is_empty() {
            format!("[{}] 已启动 · PID {}", svc.name, pid)
        } else {
            format!("[{}] 已启动 · {} · PID {}", svc.name, launch.name, pid)
        };
        self.log(&svc.id, "INFO", msg);
        self.changed();

        let m = self.clone();
        let profile = launch.profile;
        thread::spawn(move || {
            let code = child.wait().ok().and_then(|s| s.code());
            m.on_exit(svc, profile, generation, code, stopping.load(Ordering::SeqCst));
        });
    }

    fn pump<S: Read + Send + 'static>(self: &Arc<Self>, sid: String, r: S) {
        let m = self.clone();
        thread::spawn(move || {
            let reader = BufReader::new(r);
            for line in reader.lines() {
                let Ok(line) = line else { break };
                let line = line.trim_end().to_string();
                if line.is_empty() {
                    continue;
                }
                m.log(&sid, classify(&line), line);
            }
        });
    }

    fn on_exit(
        self: &Arc<Self>,
        svc: ServiceConfig,
        profile: String,
        generation: u64,
        code: Option<i32>,
        manual: bool,
    ) {
        let mut should_retry = false;
        {
            let mut procs = self.procs.lock().unwrap();
            let Some(slot) = procs.get_mut(&svc.id) else {
                return;
            };
            // 该进程已被更新的一次启动取代，忽略这次退出
            if slot.generation != generation {
                return;
            }
            reaper::untrack(slot.pgid);
            slot.pid = 0;
            if manual {
                slot.state = RunState::Stopped;
                slot.last_error.clear();
            } else {
                slot.state = RunState::Error;
                slot.errors += 1;
                slot.last_error = match code {
                    Some(c) => format!("进程退出 · 退出码 {c}"),
                    None => "进程被信号终止".to_string(),
                };
                should_retry = slot.restarts < MAX_RESTARTS;
            }
        }

        self.persist_running();

        if manual {
            self.log(&svc.id, "INFO", format!("[{}] 已停止", svc.name));
            self.changed();
            return;
        }

        let msg = match code {
            Some(c) => format!("[{}] 异常退出 · 退出码 {c}", svc.name),
            None => format!("[{}] 被信号终止", svc.name),
        };
        self.log(&svc.id, "ERROR", msg);
        self.changed();

        let auto = self.cfg.lock().unwrap().prefs.autorestart;
        if !(auto && svc.auto_restart && should_retry) {
            return;
        }

        let m = self.clone();
        thread::spawn(move || {
            let n = {
                let mut procs = m.procs.lock().unwrap();
                let Some(slot) = procs.get_mut(&svc.id) else {
                    return;
                };
                slot.restarts += 1;
                slot.restarts
            };
            // 退避间隔递增：1s、2s、4s、8s、16s
            let wait = Duration::from_secs(1u64 << (n.min(5) - 1));
            m.log(
                &svc.id,
                "WARN",
                format!(
                    "[{}] {} 秒后自动重启（第 {n}/{MAX_RESTARTS} 次）",
                    svc.name,
                    wait.as_secs()
                ),
            );
            thread::sleep(wait);
            m.spawn_as(&svc.id, &profile);
        });
    }

    fn fail(&self, id: &str, msg: String) {
        {
            let mut procs = self.procs.lock().unwrap();
            let slot = procs.entry(id.to_string()).or_insert_with(Proc::idle);
            slot.state = RunState::Error;
            slot.errors += 1;
            slot.last_error = msg.clone();
            slot.pid = 0;
        }
        let name = self
            .find(id)
            .map(|s| s.name)
            .unwrap_or_else(|| id.to_string());
        self.log(id, "ERROR", format!("[{name}] {msg}"));
        self.changed();
    }

    pub fn stop(self: &Arc<Self>, id: &str) {
        let (pgid, stopping, profile) = {
            let procs = self.procs.lock().unwrap();
            match procs.get(id) {
                Some(p) if p.state == RunState::Running && p.pgid > 0 => {
                    (p.pgid, p.stopping.clone(), p.profile.clone())
                }
                Some(_) | None => {
                    drop(procs);
                    // 未在运行时，把异常态清回已停止
                    let mut procs = self.procs.lock().unwrap();
                    if let Some(p) = procs.get_mut(id) {
                        if p.state == RunState::Error {
                            p.state = RunState::Stopped;
                        }
                    }
                    drop(procs);
                    self.changed();
                    return;
                }
            }
        };
        stopping.store(true, Ordering::SeqCst);

        let Some(svc) = self.find(id) else { return };
        let launch = svc.launch(&profile);
        let m = self.clone();
        thread::spawn(move || {
            if !launch.stop.trim().is_empty() {
                let cwd = expand_home(&svc.cwd);
                let shell = std::env::var("SHELL").unwrap_or_else(|_| "/bin/sh".into());
                let mut c = Command::new(shell);
                c.arg("-lc").arg(&launch.stop);
                if !svc.cwd.trim().is_empty() && cwd.is_dir() {
                    c.current_dir(&cwd);
                }
                for e in &launch.env {
                    if !e.k.trim().is_empty() {
                        c.env(e.k.trim(), &e.v);
                    }
                }
                c.stdin(Stdio::null())
                    .stdout(Stdio::null())
                    .stderr(Stdio::null());
                m.log(&svc.id, "INFO", format!("[{}] 执行停止命令", svc.name));
                match c.spawn() {
                    Ok(mut ch) => {
                        let _ = ch.wait();
                    }
                    Err(e) => m.log(&svc.id, "WARN", format!("[{}] 停止命令失败：{e}", svc.name)),
                }
                if m.wait_gone(&svc.id, Duration::from_secs(8)) {
                    return;
                }
                m.log(
                    &svc.id,
                    "WARN",
                    format!("[{}] 停止命令未生效，改发 SIGTERM", svc.name),
                );
            }
            unsafe { libc::kill(-pgid, libc::SIGTERM) };
            if m.wait_gone(&svc.id, Duration::from_secs(5)) {
                return;
            }
            m.log(
                &svc.id,
                "WARN",
                format!("[{}] 未响应 SIGTERM，改发 SIGKILL", svc.name),
            );
            unsafe { libc::kill(-pgid, libc::SIGKILL) };
        });
    }

    /// 轮询等待进程退出，返回是否已退出
    fn wait_gone(&self, id: &str, limit: Duration) -> bool {
        let deadline = Instant::now() + limit;
        while Instant::now() < deadline {
            if !self.is_running(id) {
                return true;
            }
            thread::sleep(Duration::from_millis(120));
        }
        !self.is_running(id)
    }

    /// 按进程当前所用的方案重启；未运行时按当前方案启动
    pub fn restart(self: &Arc<Self>, id: &str) {
        let m = self.clone();
        let id = id.to_string();
        thread::spawn(move || {
            let profile = match m.running_profile(&id) {
                Some(p) => p,
                None => match m.find(&id) {
                    Some(s) => s.profile,
                    None => return,
                },
            };
            m.stop(&id);
            m.wait_gone(&id, Duration::from_secs(10));
            {
                let mut procs = m.procs.lock().unwrap();
                if let Some(p) = procs.get_mut(&id) {
                    p.restarts += 1;
                }
            }
            m.spawn_as(&id, &profile);
        });
    }

    /// 启动所有未运行的服务，已在运行的不动
    pub fn start_all(self: &Arc<Self>) {
        for s in self.config().services {
            if !self.is_running(&s.id) {
                self.start(&s.id);
            }
        }
    }

    pub fn stop_all(self: &Arc<Self>) {
        for s in self.config().services {
            self.stop(&s.id);
        }
    }

    /// 退出前同步回收：直接向所有进程组发信号，不等待停止命令
    pub fn kill_all_now(&self) {
        let commands = self.cancel_flows();
        for g in &commands {
            reaper::untrack(*g);
            unsafe { libc::kill(-g, libc::SIGTERM) };
        }
        let mut procs = self.procs.lock().unwrap();
        for p in procs.values_mut() {
            if p.state == RunState::Running && p.pgid > 0 {
                p.stopping.store(true, Ordering::SeqCst);
                reaper::untrack(p.pgid);
                unsafe { libc::kill(-p.pgid, libc::SIGTERM) };
            }
        }
        drop(procs);
        thread::sleep(Duration::from_millis(400));
        let procs = self.procs.lock().unwrap();
        for p in procs.values() {
            if p.state == RunState::Running && p.pgid > 0 {
                unsafe { libc::kill(-p.pgid, libc::SIGKILL) };
            }
        }
        drop(procs);
        for g in &commands {
            unsafe { libc::kill(-g, libc::SIGKILL) };
        }
        let _ = std::fs::remove_file(&self.run_path);
    }

    // ── 采样 ────────────────────────────────────────────────

    pub fn snapshot(&self) -> Snapshot {
        let cfg = self.config();
        let workflows = self.flow_statuses(&cfg);
        let services = cfg.services;
        let own_pid = std::process::id();

        // 间隔太短就不重新刷新 sysinfo：CPU 是两次刷新之间的差值，
        // 间隔不足时算出来的数没有意义。跳过刷新即沿用上一次的 CPU 与内存，
        // 而状态、端口、错误这些不依赖刷新的字段照常重算，不会因此变陈旧。
        let too_soon = self
            .last_sample
            .lock()
            .unwrap()
            .map(|at: Instant| at.elapsed() < MIN_SAMPLE)
            .unwrap_or(false);

        // 每个在跑的服务的进程树，沿内核记录的父子关系逐层查，不遍历全系统进程
        let roots: Vec<(String, u32)> = {
            let procs = self.procs.lock().unwrap();
            services
                .iter()
                .filter_map(|svc| {
                    let p = procs.get(&svc.id)?;
                    (p.state == RunState::Running && p.pid != 0).then(|| (svc.id.clone(), p.pid))
                })
                .collect()
        };
        let trees: HashMap<String, Vec<Pid>> = roots
            .into_iter()
            .map(|(id, pid)| (id, tree_pids(pid)))
            .collect();

        let mut sys = self.sys.lock().unwrap();
        if !too_soon {
            // 只刷新各进程树与自身。缓存里上一轮的进程也一并刷新，
            // 已退出的由 sysinfo 移除，缓存不会越积越多
            let mut pids: Vec<Pid> = trees.values().flatten().copied().collect();
            pids.push(Pid::from_u32(own_pid));
            pids.extend(sys.processes().keys().copied());
            pids.sort_unstable();
            pids.dedup();
            // 只取 CPU 与内存，跳过磁盘等额外采集
            let kind = ProcessRefreshKind::nothing().with_memory().with_cpu();
            sys.refresh_processes_specifics(ProcessesToUpdate::Some(&pids), true, kind);
        }

        let procs = self.procs.lock().unwrap();

        // 用一次 lsof 把各进程树的监听端口一起查出来
        // lsof 一次约 46ms，按节拍每拍都跑偏重。端口起来后不会变，
        // 所以只在「这一代次还没探到端口」时查，探到即止，稳态下一次都不查。
        let mut cache = self.ports.lock().unwrap();
        let need_scan = trees.keys().any(|id| {
            let Some(p) = procs.get(id) else { return false };
            match cache.get(id) {
                Some((gen, ports)) if *gen == p.generation => {
                    // 还没探到就继续轮询，超过时限就认定它不监听端口
                    ports.is_empty() && p.started.elapsed() < PORT_SCAN_WINDOW
                }
                // 没有记录，或者进程重启换了代次
                _ => true,
            }
        });
        if need_scan {
            let all_pids: Vec<u32> = trees.values().flatten().map(|p| p.as_u32()).collect();
            let by_pid = listening_ports(&all_pids);
            for (id, pids) in &trees {
                let Some(p) = procs.get(id) else { continue };
                let mut ps: Vec<u16> = pids
                    .iter()
                    .filter_map(|x| by_pid.get(&x.as_u32()))
                    .flatten()
                    .copied()
                    .collect();
                ps.sort_unstable();
                ps.dedup();
                // 已经探到过就不要被一次空结果覆盖
                match cache.get(id) {
                    Some((gen, old)) if *gen == p.generation && !old.is_empty() => {}
                    _ => {
                        cache.insert(id.clone(), (p.generation, ps));
                    }
                }
            }
            // 已经不在运行的服务不必留着
            cache.retain(|id, _| trees.contains_key(id));
        }
        let port_map: HashMap<String, Vec<u16>> = cache
            .iter()
            .map(|(k, (_, v))| (k.clone(), v.clone()))
            .collect();
        drop(cache);

        let out = services
            .iter()
            .map(|svc| {
                let p = procs.get(&svc.id);
                let state = p.map(|x| x.state).unwrap_or(RunState::Stopped);
                let pid = p.map(|x| x.pid).unwrap_or(0);
                let running = state == RunState::Running && pid != 0;
                let tree = trees.get(&svc.id);
                let (cpu, mem) = match tree {
                    Some(pids) => tree_usage(&sys, pids),
                    None => (0.0, 0.0),
                };
                let ports: Vec<u16> = if tree.is_some() {
                    port_map.get(&svc.id).cloned().unwrap_or_default()
                } else {
                    Vec::new()
                };

                ServiceStatus {
                    id: svc.id.clone(),
                    state,
                    pid,
                    cpu,
                    mem,
                    up: if running {
                        p.map(|x| x.started.elapsed().as_secs_f64()).unwrap_or(0.0)
                    } else {
                        0.0
                    },
                    restarts: p.map(|x| x.restarts).unwrap_or(0),
                    errors: p.map(|x| x.errors).unwrap_or(0),
                    // 由进程树实际持有的端口判定，比探测「端口通不通」更准——
                    // 后者被别的程序占着也会返回真
                    port_open: svc.port != 0 && ports.contains(&svc.port),
                    ports,
                    last_error: p.map(|x| x.last_error.clone()).unwrap_or_default(),
                    profile: if running {
                        p.map(|x| x.profile.clone()).unwrap_or_default()
                    } else {
                        String::new()
                    },
                }
            })
            .collect();

        if !too_soon {
            *self.last_sample.lock().unwrap() = Some(Instant::now());
        }

        let own = sys.processes().get(&Pid::from_u32(own_pid));
        let snap = Snapshot {
            services: out,
            workflows,
            own: SelfStatus {
                pid: own_pid,
                cpu: own.map(|p| p.cpu_usage()).unwrap_or(0.0),
                mem: own.map(|p| p.memory() as f64 / 1_048_576.0).unwrap_or(0.0),
                up: self.started.elapsed().as_secs_f64(),
            },
            cores: std::thread::available_parallelism()
                .map(|n| n.get())
                .unwrap_or(1),
        };
        snap
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn classify_picks_level_from_content() {
        assert_eq!(classify("ERROR connection reset"), "ERROR");
        assert_eq!(classify("thread 'main' panicked"), "ERROR");
        assert_eq!(classify("warning: unused variable"), "WARN");
        assert_eq!(classify("vite ready in 412 ms"), "INFO");
    }

    #[test]
    fn expand_home_only_touches_leading_tilde() {
        let home = PathBuf::from(std::env::var("HOME").unwrap());
        assert_eq!(expand_home("~"), home);
        assert_eq!(expand_home("~/dev/x"), home.join("dev/x"));
        assert_eq!(expand_home("/abs/path"), PathBuf::from("/abs/path"));
        assert_eq!(expand_home("rel/~x"), PathBuf::from("rel/~x"));
    }
}

/// 回收上一轮残留的进程。
///
/// 应用被 SIGKILL（强制退出）或崩溃时来不及做任何清理，被托管的进程会活下来——
/// 它们在独立会话里，不会随父进程消失。这里读上次落盘的进程组，
/// 先用 `ps` 比对命令行确认还是同一个进程（pid 可能已被复用），再整组回收。
fn reap_orphans(run_path: &PathBuf) {
    let Ok(text) = std::fs::read_to_string(run_path) else {
        return;
    };
    let Ok(list) = serde_json::from_str::<Vec<RunningEntry>>(&text) else {
        let _ = std::fs::remove_file(run_path);
        return;
    };

    let mut killed = Vec::new();
    for e in &list {
        if e.pid == 0 || e.pgid <= 0 {
            continue;
        }
        let out = Command::new("ps")
            .args(["-o", "command=", "-p", &e.pid.to_string()])
            .output();
        let alive_cmd = match out {
            Ok(o) if o.status.success() => String::from_utf8_lossy(&o.stdout).trim().to_string(),
            _ => String::new(),
        };
        // pid 还在，且命令行仍是当初那条，才认定是我们留下的
        if alive_cmd.is_empty() || !alive_cmd.contains(e.cmd.trim()) {
            continue;
        }
        unsafe { libc::kill(-e.pgid, libc::SIGTERM) };
        killed.push(e.id.clone());
    }

    if !killed.is_empty() {
        thread::sleep(Duration::from_millis(600));
        for e in &list {
            if killed.contains(&e.id) && e.pgid > 0 {
                unsafe { libc::kill(-e.pgid, libc::SIGKILL) };
            }
        }
        eprintln!("已回收上次残留的进程：{}", killed.join(", "));
    }
    let _ = std::fs::remove_file(run_path);
}

/// 探测这批进程实际在监听哪些端口。
///
/// 有些工具在配置的端口被占用时会自动改用别的端口，光看配置值不准。
/// 限定 pid 后 lsof 单次约 47ms，相对 1.4 秒的采样节拍可以接受；
/// `-n` `-P` 关掉域名与端口名解析，避免额外的解析开销。
fn listening_ports(pids: &[u32]) -> HashMap<u32, Vec<u16>> {
    let mut out: HashMap<u32, Vec<u16>> = HashMap::new();
    if pids.is_empty() {
        return out;
    }
    let list = pids
        .iter()
        .map(|p| p.to_string())
        .collect::<Vec<_>>()
        .join(",");
    let Ok(o) = Command::new("lsof")
        .args([
            "-nP",
            "-F",
            "pn",
            "-a",
            "-iTCP",
            "-sTCP:LISTEN",
            "-p",
            &list,
        ])
        .output()
    else {
        return out;
    };

    let text = String::from_utf8_lossy(&o.stdout);
    let mut cur: u32 = 0;
    for line in text.lines() {
        let mut chars = line.chars();
        let Some(tag) = chars.next() else { continue };
        let rest = chars.as_str();
        match tag {
            'p' => cur = rest.parse().unwrap_or(0),
            // 地址形如 127.0.0.1:5173、*:5173、[::1]:8080，端口在最后一段
            'n' => {
                if cur == 0 {
                    continue;
                }
                if let Some(port) = rest.rsplit(':').next().and_then(|s| s.parse::<u16>().ok()) {
                    if port != 0 {
                        let e = out.entry(cur).or_default();
                        if !e.contains(&port) {
                            e.push(port);
                        }
                    }
                }
            }
            _ => {}
        }
    }
    out
}

/// 收集进程树上的全部 pid
fn tree_pids(root: u32) -> Vec<Pid> {
    let mut seen: HashSet<u32> = HashSet::new();
    let mut stack = vec![root];
    while let Some(pid) = stack.pop() {
        if !seen.insert(pid) {
            continue;
        }
        stack.extend(child_pids(pid));
    }
    seen.into_iter().map(Pid::from_u32).collect()
}

/// 直接子进程。proc_listchildpids 返回的是个数，缓冲区填满时加倍重取
fn child_pids(ppid: u32) -> Vec<u32> {
    let mut buf = vec![0 as libc::pid_t; 64];
    loop {
        let bytes = (buf.len() * std::mem::size_of::<libc::pid_t>()) as libc::c_int;
        let n = unsafe { libc::proc_listchildpids(ppid as libc::pid_t, buf.as_mut_ptr().cast(), bytes) };
        if n <= 0 {
            return Vec::new();
        }
        let n = n as usize;
        if n < buf.len() {
            return buf[..n].iter().map(|&p| p as u32).collect();
        }
        buf.resize(buf.len() * 2, 0);
    }
}

/// 累计进程树的 CPU 与常驻内存，内存单位 MB
fn tree_usage(sys: &System, pids: &[Pid]) -> (f32, f64) {
    let mut cpu = 0.0f32;
    let mut mem = 0.0f64;
    for pid in pids {
        if let Some(p) = sys.processes().get(pid) {
            cpu += p.cpu_usage();
            mem += p.memory() as f64 / 1_048_576.0;
        }
    }
    (cpu, mem)
}
