use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Clone, Debug, Default, PartialEq)]
pub struct EnvVar {
    pub k: String,
    pub v: String,
}

/// 默认方案的 id，指服务自身的命令与环境变量
pub const DEFAULT_PROFILE: &str = "default";

fn default_profile() -> String {
    DEFAULT_PROFILE.to_string()
}

/// 服务的另一套启动方式。命令留空时沿用服务自身的，环境变量按名覆盖或追加
#[derive(Serialize, Deserialize, Clone, Debug, Default)]
pub struct Profile {
    pub id: String,
    pub name: String,
    #[serde(default)]
    pub cmd: String,
    #[serde(default)]
    pub stop: String,
    #[serde(default)]
    pub env: Vec<EnvVar>,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct ServiceConfig {
    pub id: String,
    pub name: String,
    pub proj: String,
    /// 图标键，对应前端 IC 表
    pub ic: String,
    /// 启动命令，交给登录 shell 执行
    pub cmd: String,
    /// 停止命令，为空时直接向进程组发信号
    pub stop: String,
    pub cwd: String,
    /// 0 表示不监听端口
    pub port: u16,
    pub auto_restart: bool,
    pub env: Vec<EnvVar>,
    /// 当前方案，不带方案的启动都按它
    #[serde(default = "default_profile")]
    pub profile: String,
    #[serde(default)]
    pub profiles: Vec<Profile>,
}

/// 服务按某个方案启动时实际使用的配置
#[derive(Clone, Debug, PartialEq)]
pub struct Launch {
    /// 实际采用的方案 id。找不到的 id 按默认方案处理
    pub profile: String,
    /// 方案名，默认方案为空
    pub name: String,
    pub cmd: String,
    pub stop: String,
    pub env: Vec<EnvVar>,
}

impl ServiceConfig {
    pub fn launch(&self, profile: &str) -> Launch {
        let Some(p) = self.profiles.iter().find(|p| p.id == profile) else {
            return Launch {
                profile: DEFAULT_PROFILE.to_string(),
                name: String::new(),
                cmd: self.cmd.clone(),
                stop: self.stop.clone(),
                env: self.env.clone(),
            };
        };
        let mut env = self.env.clone();
        for e in &p.env {
            let k = e.k.trim();
            if k.is_empty() {
                continue;
            }
            match env.iter_mut().find(|x| x.k.trim() == k) {
                Some(x) => x.v = e.v.clone(),
                None => env.push(EnvVar { k: k.to_string(), v: e.v.clone() }),
            }
        }
        let pick = |own: &str, base: &str| {
            if own.trim().is_empty() { base.to_string() } else { own.to_string() }
        };
        Launch {
            profile: p.id.clone(),
            name: p.name.clone(),
            cmd: pick(&p.cmd, &self.cmd),
            stop: pick(&p.stop, &self.stop),
            env,
        }
    }
}

#[derive(Serialize, Deserialize, Clone, Copy, Debug, Default, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum StepKind {
    #[default]
    Service,
    Command,
}

#[derive(Serialize, Deserialize, Clone, Copy, Debug, Default, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum ReadyKind {
    /// 进程树开始监听任一端口
    #[default]
    Port,
    /// 启动后等待固定秒数，期间进程退出视为失败
    Delay,
}

/// 工作流里的一步。服务步骤与命令步骤共用一个结构，表单切换类型时不丢已填的内容
#[derive(Serialize, Deserialize, Clone, Debug, Default)]
#[serde(rename_all = "camelCase")]
pub struct Step {
    pub id: String,
    #[serde(default)]
    pub kind: StepKind,
    /// 服务步骤：服务 id
    #[serde(default)]
    pub service: String,
    /// 服务步骤：方案 id，空串表示跟随服务的当前方案
    #[serde(default)]
    pub profile: String,
    #[serde(default)]
    pub ready: ReadyKind,
    /// 命令步骤：显示名
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub cmd: String,
    #[serde(default)]
    pub cwd: String,
    /// 等待端口与命令步骤是超时秒数，按时长就绪是等待秒数
    #[serde(default)]
    pub seconds: u64,
}

#[derive(Serialize, Deserialize, Clone, Debug, Default)]
pub struct Stage {
    pub id: String,
    #[serde(default)]
    pub steps: Vec<Step>,
}

/// 按阶段顺序执行的一组步骤，同一阶段内的步骤同时开始
#[derive(Serialize, Deserialize, Clone, Debug, Default)]
pub struct Workflow {
    pub id: String,
    pub name: String,
    /// 图标底色的键，由界面解释
    #[serde(default)]
    pub color: String,
    #[serde(default)]
    pub stages: Vec<Stage>,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct Prefs {
    pub autostart: bool,
    pub autorestart: bool,
    /// 已无对应功能，只为让旧版（Tauri）还能读这份配置：它缺字段会整份解析失败，退回空配置
    #[serde(default)]
    pub notify: bool,
    pub quiet: bool,
}

impl Default for Prefs {
    fn default() -> Self {
        Self {
            autostart: false,
            autorestart: true,
            notify: false,
            quiet: true,
        }
    }
}

#[derive(Serialize, Deserialize, Clone, Debug, Default)]
pub struct AppConfig {
    #[serde(default)]
    pub services: Vec<ServiceConfig>,
    #[serde(default)]
    pub workflows: Vec<Workflow>,
    #[serde(default)]
    pub prefs: Prefs,
}

#[derive(Serialize, Deserialize, Clone, Copy, Debug, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum RunState {
    Running,
    Stopped,
    Error,
}

#[derive(Serialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct ServiceStatus {
    pub id: String,
    pub state: RunState,
    pub pid: u32,
    /// 进程树 CPU 占用百分比，单核为 100
    pub cpu: f32,
    /// 进程树常驻内存，单位 MB
    pub mem: f64,
    /// 运行秒数
    pub up: f64,
    pub restarts: u32,
    pub errors: u32,
    /// 配置的端口是否确实由本服务的进程树在监听
    pub port_open: bool,
    /// 实际探测到的监听端口。有些工具在端口被占用时会自动改用别的端口
    pub ports: Vec<u16>,
    pub last_error: String,
    /// 运行中的进程所用的方案，未运行时为空
    pub profile: String,
}

#[derive(Serialize, Clone, Copy, Debug, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum FlowState {
    /// 本次应用运行期间还没执行过
    Idle,
    Running,
    Done,
    Failed,
    Stopped,
}

#[derive(Serialize, Clone, Copy, Debug, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum StepState {
    Pending,
    Running,
    Done,
    Failed,
    /// 前面的阶段失败或工作流被停止，没有执行
    Skipped,
    /// 执行过，此刻服务已停止或换了方案；命令步骤在工作流停止后也是这个状态
    Stopped,
}

#[derive(Serialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct StepStatus {
    pub id: String,
    pub state: StepState,
    /// 结果或失败原因，例如「端口 8080」「退出码 1」
    pub detail: String,
    /// 已执行的秒数，结束后固定为总耗时
    pub elapsed: f64,
}

#[derive(Serialize, Clone, Debug)]
pub struct FlowEvent {
    /// Unix 毫秒
    pub ts: u64,
    /// start、done、error 或 info
    pub kind: String,
    pub text: String,
}

#[derive(Serialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowStatus {
    pub id: String,
    pub state: FlowState,
    /// 正在执行或停下时所在的阶段，从 0 起
    pub stage: usize,
    /// 本次运行开始的 Unix 毫秒，未运行过为 0
    pub started: u64,
    pub elapsed: f64,
    pub steps: Vec<StepStatus>,
    /// 失败原因
    pub message: String,
    pub events: Vec<FlowEvent>,
    /// 工作流涉及的服务数
    pub members: usize,
    /// 其中正按工作流指定的方案运行的服务数
    pub matched: usize,
}

#[derive(Serialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct SelfStatus {
    pub pid: u32,
    pub cpu: f32,
    pub mem: f64,
    pub up: f64,
}

#[derive(Serialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Snapshot {
    pub services: Vec<ServiceStatus>,
    pub workflows: Vec<WorkflowStatus>,
    pub own: SelfStatus,
    /// 逻辑核心数。cpu 是「占单核的百分比」，要换算成占整机多少得除以它
    pub cores: usize,
}

#[derive(Serialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct LogLine {
    pub id: String,
    /// Unix 毫秒，时分秒由前端格式化
    pub ts: u64,
    pub lvl: String,
    pub txt: String,
    /// 来源服务 id
    pub sid: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn env(pairs: &[(&str, &str)]) -> Vec<EnvVar> {
        pairs
            .iter()
            .map(|(k, v)| EnvVar { k: k.to_string(), v: v.to_string() })
            .collect()
    }

    fn service() -> ServiceConfig {
        ServiceConfig {
            id: "web".into(),
            name: "web".into(),
            proj: String::new(),
            ic: "web".into(),
            cmd: "npm run dev".into(),
            stop: "npm run stop".into(),
            cwd: String::new(),
            port: 0,
            auto_restart: false,
            env: env(&[("USER_CLIENT", "dev"), ("DEBUG", "1")]),
            profile: DEFAULT_PROFILE.into(),
            profiles: vec![
                Profile {
                    id: "test".into(),
                    name: "test 环境".into(),
                    cmd: String::new(),
                    stop: String::new(),
                    env: env(&[("USER_CLIENT", "test"), ("EXTRA", "x")]),
                },
                Profile {
                    id: "webpack".into(),
                    name: "webpack".into(),
                    cmd: "npm run dev:webpack".into(),
                    stop: "  ".into(),
                    env: vec![],
                },
            ],
        }
    }

    #[test]
    fn default_and_unknown_profiles_use_service_fields() {
        let s = service();
        for id in [DEFAULT_PROFILE, "", "gone"] {
            let l = s.launch(id);
            assert_eq!(l.profile, DEFAULT_PROFILE);
            assert_eq!(l.cmd, "npm run dev");
            assert_eq!(l.env, s.env);
        }
    }

    #[test]
    fn profile_env_overrides_by_name_and_appends_new_names() {
        let l = service().launch("test");
        assert_eq!(l.profile, "test");
        assert_eq!(l.cmd, "npm run dev", "留空的启动命令沿用服务的");
        assert_eq!(l.stop, "npm run stop");
        assert_eq!(l.env, env(&[("USER_CLIENT", "test"), ("DEBUG", "1"), ("EXTRA", "x")]));
    }

    #[test]
    fn profile_command_replaces_and_blank_stop_falls_back() {
        let l = service().launch("webpack");
        assert_eq!(l.cmd, "npm run dev:webpack");
        assert_eq!(l.stop, "npm run stop", "只有空白的停止命令按留空处理");
    }

    #[test]
    fn old_config_without_new_fields_still_parses() {
        let raw = r#"{"services":[{"id":"a","name":"a","proj":"","ic":"web","cmd":"x","stop":"","cwd":"","port":0,"autoRestart":true,"env":[]}],"prefs":{"autostart":false,"autorestart":true,"quiet":true}}"#;
        let cfg: AppConfig = serde_json::from_str(raw).unwrap();
        assert_eq!(cfg.services[0].profile, DEFAULT_PROFILE);
        assert!(cfg.services[0].profiles.is_empty());
        assert!(cfg.workflows.is_empty());
    }
}
