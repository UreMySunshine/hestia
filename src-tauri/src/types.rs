use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Clone, Debug, Default)]
pub struct EnvVar {
    pub k: String,
    pub v: String,
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
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct Prefs {
    pub autostart: bool,
    pub autorestart: bool,
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
