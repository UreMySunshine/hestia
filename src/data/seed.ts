import type { PrefKey, ServiceState } from "../types";

export const LABEL: Record<ServiceState, string> = {
  running: "运行中",
  stopped: "已停止",
  error: "异常",
};

export interface TourStep {
  path: string;
  title: string;
  cta: string;
  body: string;
  points: { t: string }[];
}

export const TOUR: TourStep[] = [
  {
    // 空串表示这一步用应用图标而不是线条图形，见 overlays/Tour.tsx
    path: "",
    title: "欢迎使用 Hestia",
    cta: "下一步",
    body: "把本地开发要用到的服务和脚本集中管起来：一处启动、一处停止、一处看日志。",
    points: [
      { t: "仪表盘一眼看清所有服务状态" },
      { t: "服务详情内嵌实时日志与资源曲线" },
      { t: "⌘K 随时启停任意服务" },
    ],
  },
  {
    path: "M12 5.5v13M5.5 12h13",
    title: "保存你的第一条启动命令",
    cta: "开始使用",
    body: "填写工作目录、启动命令和停止命令，Hestia 会把它保存下来供以后复用。",
    points: [
      { t: "支持 npm / pnpm / docker / cargo 等任意命令" },
      { t: "可为每个服务单独配置环境变量" },
      { t: "崩溃后可自动重启" },
    ],
  },
];

export const SHORTCUTS = [
  { label: "命令面板", key: "⌘K" },
  { label: "全部启动", key: "⇧⌘R" },
  { label: "全部停止", key: "⇧⌘." },
  { label: "开关日志抽屉", key: "⌘L" },
  { label: "切换深浅色", key: "⌘⇧T" },
];

export const PREF_ITEMS: { key: PrefKey; label: string; hint: string }[] = [
  {
    key: "autostart",
    label: "开机自启 Hestia",
    hint: "登录后自动在菜单栏常驻",
  },
  {
    key: "autorestart",
    label: "服务崩溃后自动重启",
    hint: "最多重试 5 次，退避间隔递增",
  },
  {
    key: "notify",
    label: "异常时系统通知",
    hint: "进程退出或错误频率异常时提醒",
  },
  {
    key: "quiet",
    label: "隐藏未运行服务的资源曲线",
    hint: "减少仪表盘上的无效信息",
  },
];
