/** Unix 毫秒转本地时分秒 */
export function hhmmss(ts: number): string {
  return new Date(ts).toTimeString().slice(0, 8);
}

/** 秒数格式化为运行时长 */
export function fmtUp(v: number): string {
  if (!v) return "—";
  const h = Math.floor(v / 3600);
  const m = Math.floor((v % 3600) / 60);
  return h ? `${h} 小时 ${m} 分` : `${m} 分 ${Math.floor(v % 60)} 秒`;
}

/**
 * 采样数组转 polyline points。
 * max 为 0 时按数组自身最大值归一，曲线只占用 90% 高度留出上边距。
 */
export function pts(a: number[], max: number, w: number, h: number): string {
  const m = max || Math.max(...a, 1);
  return a
    .map(
      (v, i) =>
        `${(i * (w / (a.length - 1))).toFixed(1)},${(
          h -
          (Math.min(v, m) / m) * h * 0.9
        ).toFixed(1)}`,
    )
    .join(" ");
}

/** 折线补上左右底角，闭合成填充区域 */
export function areaPts(line: string, w: number, h: number): string {
  return `0,${h} ${line} ${w},${h}`;
}
