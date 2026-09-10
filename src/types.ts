export type ServiceState = "running" | "stopped" | "error";

export type Screen =
  | "overview"
  | "detail"
  | "new"
  | "monitor"
  | "settings";

export type Theme = "dark" | "light";

export type IconKey =
  | "web"
  | "api"
  | "db"
  | "layers"
  | "queue"
  | "doc"
  | "tunnel"
  | "chip"
  | "pulse";

export type LogLevel = "INFO" | "WARN" | "ERROR";

export type LogMode = "THIS" | "ERR" | "ALL";

export type FilterLabel = "全部" | "运行中" | "已停止" | "异常";

/** 监控面板的排序方式 */
export type MonitorSort = "默认" | "CPU" | "内存" | "名称";

export interface EnvVar {
  k: string;
  v: string;
}

// ── 与 Rust 侧一一对应的结构 ──────────────────────────────

export interface ServiceConfig {
  id: string;
  name: string;
  proj: string;
  ic: IconKey;
  cmd: string;
  stop: string;
  cwd: string;
  /** 0 表示不监听端口 */
  port: number;
  autoRestart: boolean;
  env: EnvVar[];
}


export type PrefKey = "autostart" | "autorestart" | "notify" | "quiet";

export type Prefs = Record<PrefKey, boolean>;

export interface AppConfig {
  services: ServiceConfig[];
  prefs: Prefs;
}

export interface ServiceStatus {
  id: string;
  state: ServiceState;
  pid: number;
  /** 进程树 CPU 百分比，单核为 100 */
  cpu: number;
  /** 进程树常驻内存，MB */
  mem: number;
  /** 运行秒数 */
  up: number;
  restarts: number;
  errors: number;
  /** 配置的端口是否确实由本服务的进程树在监听 */
  portOpen: boolean;
  /** 实际探测到的监听端口。有些工具在端口被占用时会自动改用别的端口 */
  ports: number[];
  lastError: string;
}

export interface SelfStatus {
  pid: number;
  cpu: number;
  mem: number;
  up: number;
}

export interface Snapshot {
  services: ServiceStatus[];
  own: SelfStatus;
  /** 逻辑核心数。cpu 是「占单核的百分比」，换算成占整机多少要除以它 */
  cores: number;
}

export interface LogLine {
  id: string;
  /** Unix 毫秒 */
  ts: number;
  lvl: LogLevel;
  txt: string;
  /** 来源服务 id */
  sid: string;
}


// ── 前端合并后的服务视图 ──────────────────────────────────

export interface Service extends ServiceConfig, Omit<ServiceStatus, "id"> {
  /** CPU 采样历史，40 个点 */
  hist: number[];
  /** 内存采样历史，40 个点 */
  mhist: number[];
}

export interface SelfProc extends SelfStatus {
  hist: number[];
}

/** 新建 / 编辑服务表单 */
export interface ServiceForm {
  id: string;
  name: string;
  proj: string;
  kind: IconKey;
  cwd: string;
  cmd: string;
  stop: string;
  port: string;
  restart: boolean;
  env: EnvVar[];
}


export interface State {
  screen: Screen;
  theme: Theme;
  q: string;
  filter: FilterLabel;
  /** 监控面板的搜索、筛选、排序。与仪表盘的 q / filter 分开，两处切换互不影响 */
  monQ: string;
  monFilter: FilterLabel;
  monSort: MonitorSort;
  sel: string;
  drawerOpen: boolean;
  view: "grid" | "list";
  follow: boolean;
  logMode: LogMode;
  cmdkOpen: boolean;
  cmdQ: string;
  envSel: string;
  /** null 表示引导未打开 */
  tourStep: number | null;
  form: ServiceForm;
  formMode: "new" | "edit";
  prefs: Prefs;
  services: Service[];
  self: SelfProc;
  logs: LogLine[];
  /** 全局 CPU 曲线，单位与 cpu 相同 */
  gcpu: number[];
  /** 全局内存曲线，单位 MB */
  gmem: number[];
  /** 逻辑核心数，用于把「占单核」换算成「占整机」 */
  cores: number;
  /** 是否已从后端载入过配置 */
  ready: boolean;
}
