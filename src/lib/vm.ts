import { IC, UI } from "../data/icons";
import { LABEL } from "../data/seed";
import type { Service, Theme } from "../types";
import { fmtUp, pts } from "./format";

export interface ServiceVM {
  stateLabel: string;
  iconPath: string;
  btnPath: string;
  dot: string;
  pulse: string;
  pillBg: string;
  pillBd: string;
  pillTx: string;
  iconBg: string;
  iconBd: string;
  iconTx: string;
  /** 迷你曲线描边色 */
  line: string;
  /** 迷你曲线填充色 */
  fill: string;
  cpu: string;
  mem: number;
  cpuColor: string;
  /** 采样窗口内的 CPU 峰值，口径同 cpu（占单核的百分比） */
  peakCpu: string;
  /** 采样窗口内的常驻内存峰值，单位 MB */
  peakMem: number;
  portLabel: string;
  portShort: string;
  /** 实际生效的端口，优先用探测到的 */
  port: number;
  /** 配置了端口，但实际监听的是另一个 */
  portDrift: boolean;
  uptimeLabel: string;
  spark: string;
  sparkArea: string;
  metaLine: string;
  btnLabel: string;
  btnBg: string;
  btnBd: string;
  btnTx: string;
}

/** 由服务状态推导出的全部视觉取值，与设计稿 vm() 一一对应 */
export function serviceVM(s: Service, cores = 1): ServiceVM {
  const run = s.state === "running";
  const err = s.state === "error";
  const key = run ? "var(--ok)" : err ? "var(--err)" : "var(--dim)";
  const peakCpu = Math.max(...s.hist, 0);
  // 曲线按自身峰值归一，否则固定拿 100 当满刻度时，超过一个核的部分会被削平成直线。
  // 但下限压在 25，免得一个常年 0.3% 的进程被放大成剧烈起伏。
  const spark = pts(s.hist, Math.max(peakCpu, 25), 100, 24);

  return {
    stateLabel: LABEL[s.state] || "已停止",
    iconPath: IC[s.ic] || IC.chip,
    btnPath: run ? UI.stop : UI.play,
    dot: key,
    pulse: run ? "glow 2.4s ease-in-out infinite" : "none",
    pillBg: run
      ? "rgba(74,222,155,.14)"
      : err
        ? "rgba(255,111,145,.14)"
        : "var(--sunk)",
    pillBd: run
      ? "rgba(74,222,155,.4)"
      : err
        ? "rgba(255,111,145,.4)"
        : "var(--line2)",
    pillTx: key,
    iconBg: run
      ? "linear-gradient(150deg,rgba(255,138,91,.42),rgba(255,138,91,.1))"
      : err
        ? "linear-gradient(150deg,rgba(255,111,145,.42),rgba(255,111,145,.1))"
        : "var(--sunk)",
    iconBd: run
      ? "rgba(255,138,91,.45)"
      : err
        ? "rgba(255,111,145,.45)"
        : "var(--line2)",
    iconTx: run || err ? "var(--onAc)" : "var(--dim)",
    line: run ? "#FF8A5B" : "rgba(160,175,205,.45)",
    fill: run ? "rgba(255,138,91,.18)" : "transparent",
    cpu: s.cpu.toFixed(1),
    mem: Math.round(s.mem),
    peakCpu: peakCpu.toFixed(1),
    peakMem: Math.round(Math.max(...s.mhist, 0)),
    // cpu 是「占单核」的值，阈值要按整机容量折算：
    // 设计稿的 50 / 25 是在「100 就是满」的前提下定的
    cpuColor:
      s.cpu > cores * 50 ? "var(--err)" : s.cpu > cores * 25 ? "var(--warn)" : "var(--tx)",
    ...portFields(s),
    uptimeLabel: run ? fmtUp(s.up) : "未运行",
    spark,
    sparkArea: `0,24 ${spark} 100,24`,
    metaLine: `${run ? `PID ${s.pid}` : "未运行"} · 重启 ${s.restarts} 次 · ${s.proj}`,
    btnLabel: run ? "停止" : "启动",
    btnBg: run
      ? "var(--glass)"
      : "linear-gradient(150deg,rgba(255,138,91,.5),rgba(255,138,91,.16))",
    btnBd: run ? "var(--line)" : "rgba(255,138,91,.55)",
    btnTx: run ? "var(--mu)" : "var(--onAc)",
  };
}

/**
 * 端口相关取值。
 * 优先采用实际探测到的监听端口——不少工具在配置端口被占用时会自动改用别的端口，
 * 只看配置值会对不上。
 */
function portFields(s: Service) {
  const found = s.ports ?? [];
  const shown = found.length ? found : s.port ? [s.port] : [];
  const label =
    shown.length === 0
      ? "无端口"
      : shown.length <= 2
        ? `端口 ${shown.join(" / ")}`
        : `端口 ${shown.slice(0, 2).join(" / ")} +${shown.length - 2}`;
  return {
    portLabel: label,
    portShort: shown.length ? String(shown[0]) : "",
    port: shown[0] ?? 0,
    portDrift: s.port !== 0 && found.length > 0 && !found.includes(s.port),
  };
}

/** 选中态配色，浅色主题下用品牌橙，深色主题下用白 */
export function accents(theme: Theme) {
  const light = theme === "light";
  return {
    onGlass: light ? "rgba(217,84,44,.14)" : "rgba(255,255,255,.14)",
    selBd: light ? "rgba(217,84,44,.42)" : "var(--line)",
    selTx: light ? "var(--ac)" : "var(--tx)",
  };
}
