import type { CSSProperties } from "react";

interface IconProps {
  d: string;
  size?: number;
  sw?: number;
  style?: CSSProperties;
}

/** 24×24 线性图标 */
export function Icon({ d, size = 16, sw = 1.8, style }: IconProps) {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={sw}
      strokeLinecap="round"
      strokeLinejoin="round"
      style={{ width: size, height: size, ...style }}
    >
      <path d={d} />
    </svg>
  );
}

/** 品牌标记 */
interface SparklineProps {
  points: string;
  area: string;
  stroke: string;
  fill: string;
  strokeWidth?: number;
  opacity?: number;
  viewBox?: string;
  style?: CSSProperties;
}

/** 折线 + 填充区域的迷你曲线 */
export function Sparkline({
  points,
  area,
  stroke,
  fill,
  strokeWidth = 1.8,
  opacity,
  viewBox = "0 0 100 24",
  style,
}: SparklineProps) {
  return (
    <svg
      viewBox={viewBox}
      preserveAspectRatio="none"
      style={{ display: "block", ...style }}
    >
      <polyline points={area} fill={fill} stroke="none" />
      <polyline
        points={points}
        fill="none"
        stroke={stroke}
        strokeWidth={strokeWidth}
        strokeLinecap="round"
        strokeLinejoin="round"
        vectorEffect="non-scaling-stroke"
        opacity={opacity}
      />
    </svg>
  );
}

/** 44×26 开关 */
export function Toggle({
  on,
  onClick,
  label,
}: {
  on: boolean;
  onClick: () => void;
  label: string;
}) {
  return (
    <button
      onClick={onClick}
      aria-label={label}
      style={{
        width: 44,
        height: 26,
        flex: "none",
        borderRadius: 14,
        border: `1px solid ${on ? "rgba(255,138,91,.55)" : "var(--line2)"}`,
        background: on
          ? "linear-gradient(150deg,rgba(255,138,91,.55),rgba(255,138,91,.25))"
          : "var(--sunk)",
        cursor: "pointer",
        padding: 2,
        display: "flex",
        alignItems: "center",
        justifyContent: on ? "flex-end" : "flex-start",
        fontFamily: "inherit",
      }}
    >
      <span
        style={{
          width: 20,
          height: 20,
          borderRadius: "50%",
          display: "block",
          background: on ? "var(--onAc)" : "var(--mu)",
          boxShadow: "0 2px 5px rgba(0,0,0,.25)",
        }}
      />
    </button>
  );
}

/** 状态圆点 */
export function Dot({
  color,
  size = 7,
  pulse,
  glow = true,
  style,
}: {
  color: string;
  size?: number;
  pulse?: string;
  glow?: boolean;
  style?: CSSProperties;
}) {
  return (
    <span
      style={{
        width: size,
        height: size,
        borderRadius: "50%",
        flex: "none",
        background: color,
        boxShadow: glow ? `0 0 8px ${color}` : undefined,
        animation: pulse,
        ...style,
      }}
    />
  );
}

/**
 * 背景的三团弥散光晕，样式与设计稿一致。
 * 暂停逻辑见 styles.css 里的 .blob 与 lib/useAmbientMotion.ts。
 */
export function Blobs() {
  const base: CSSProperties = {
    position: "absolute",
    borderRadius: "50%",
    opacity: "var(--blobOp)" as unknown as number,
  };
  const blobs = [
    {
      style: { width: 620, height: 620, left: -140, top: -180, filter: "blur(30px)" },
      color: "var(--b1)",
      animation: "drift 18s ease-in-out infinite",
    },
    {
      style: { width: 680, height: 680, right: -160, top: -120, filter: "blur(30px)" },
      color: "var(--b2)",
      animation: "drift 22s ease-in-out infinite reverse",
    },
    {
      style: { width: 720, height: 720, left: "28%", bottom: -320, filter: "blur(34px)" },
      color: "var(--b3)",
      animation: "drift 26s ease-in-out infinite",
    },
  ];
  return (
    <div
      style={{
        position: "absolute",
        inset: 0,
        overflow: "hidden",
        pointerEvents: "none",
      }}
    >
      {blobs.map((b, i) => (
        <div
          key={i}
          className="blob"
          style={{
            ...base,
            ...b.style,
            background: `radial-gradient(circle,${b.color},transparent 65%)`,
            animation: b.animation,
          }}
        />
      ))}
    </div>
  );
}
