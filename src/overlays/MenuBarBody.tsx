import { serviceVM } from "../lib/vm";
import type { Service } from "../types";
import appIcon from "../assets/app-icon.png";
import { Icon } from "../components/primitives";

interface BodyProps {
  services: Service[];
  /** 逻辑核心数，用于把「占单核」的 CPU 折算成占整机 */
  cores: number;
  onToggle: (s: Service) => void;
  onStartAll: () => void;
  onStopAll: () => void;
  /** 独立菜单栏窗口里点击标题行可以唤起主窗口 */
  onOpenMain?: () => void;
}

/** 面板本体，主窗口内的预览与独立菜单栏窗口共用 */
export function MenuBarBody({
  services,
  cores,
  onToggle,
  onStartAll,
  onStopAll,
  onOpenMain,
}: BodyProps) {
  const runningCount = services.filter((s) => s.state === "running").length;
  const totalCpu = services.reduce((a, s) => a + s.cpu, 0);
  const totalMem = services.reduce((a, s) => a + s.mem, 0);

  return (
    <>
      <div
        onClick={onOpenMain}
        style={{
          display: "flex",
          alignItems: "center",
          gap: 9,
          padding: "2px 4px",
          cursor: onOpenMain ? "pointer" : undefined,
        }}
        title={onOpenMain ? "打开主窗口" : undefined}
      >
        <img
          src={appIcon}
          alt=""
          style={{
            width: 24,
            height: 24,
            flex: "none",
            borderRadius: 8,
            objectFit: "cover",
            border: "1px solid var(--brandBd)",
          }}
        />
        <span style={{ fontSize: 13, fontWeight: 600 }}>Hestia</span>
        <span style={{ flex: 1 }} />
        <span style={{ fontSize: 11, color: "var(--dim)" }}>
          {runningCount}/{services.length} 运行中
        </span>
      </div>

      <div style={{ display: "flex", gap: 8, padding: "0 2px" }}>
        {[
          {
            label: "CPU",
            value: `${(totalCpu / Math.max(1, cores)).toFixed(0)}%`,
            color: "var(--ac)",
          },
          {
            label: "内存",
            value: `${(totalMem / 1024).toFixed(1)}G`,
            color: "var(--cy)",
          },
        ].map((x) => (
          <div
            key={x.label}
            style={{
              flex: 1,
              background: "var(--sunk)",
              border: "1px solid var(--line2)",
              borderRadius: 13,
              padding: "9px 11px",
            }}
          >
            <div style={{ fontSize: 10.5, color: "var(--dim)" }}>{x.label}</div>
            <div
              style={{
                fontSize: 17,
                fontWeight: 600,
                marginTop: 3,
                color: x.color,
              }}
            >
              {x.value}
            </div>
          </div>
        ))}
      </div>

      <div
        style={{
          display: "flex",
          flexDirection: "column",
          gap: 2,
          maxHeight: 244,
          overflowY: "auto",
        }}
      >
        {services.length === 0 && (
          <div
            style={{
              fontSize: 12,
              color: "var(--dim)",
              padding: "12px 8px",
              textAlign: "center",
            }}
          >
            还没有配置服务
          </div>
        )}
        {services.map((s) => {
          const v = serviceVM(s);
          return (
            <div
              key={s.id}
              className="row-hover"
              style={{
                display: "flex",
                alignItems: "center",
                gap: 9,
                padding: "7px 8px",
                borderRadius: 12,
              }}
            >
              <span
                style={{
                  width: 7,
                  height: 7,
                  borderRadius: "50%",
                  flex: "none",
                  background: v.dot,
                  boxShadow: `0 0 7px ${v.dot}`,
                }}
              />
              <span
                style={{
                  flex: 1,
                  minWidth: 0,
                  fontSize: 12.5,
                  overflow: "hidden",
                  textOverflow: "ellipsis",
                  whiteSpace: "nowrap",
                }}
              >
                {s.name}
              </span>
              <span
                style={{
                  fontSize: 11,
                  color: "var(--dim)",
                  fontFamily: "JetBrains Mono,monospace",
                }}
              >
                {v.cpu}%
              </span>
              <button
                onClick={() => onToggle(s)}
                title={v.btnLabel}
                aria-label={v.btnLabel}
                style={{
                  width: 28,
                  height: 24,
                  flex: "none",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  borderRadius: 9,
                  cursor: "pointer",
                  fontFamily: "inherit",
                  background: v.btnBg,
                  border: `1px solid ${v.btnBd}`,
                  color: v.btnTx,
                }}
              >
                <Icon d={v.btnPath} size={14} sw={1.9} />
              </button>
            </div>
          );
        })}
      </div>

      <div
        style={{
          display: "flex",
          gap: 8,
          borderTop: "1px solid var(--line2)",
          padding: "10px 2px 2px",
        }}
      >
        <button
          onClick={onStartAll}
          style={{
            flex: 1,
            border: "1px solid rgba(255,138,91,.55)",
            borderRadius: 12,
            background:
              "linear-gradient(150deg,rgba(255,138,91,.5),rgba(255,138,91,.16))",
            color: "var(--onAc)",
            padding: 8,
            fontSize: 12,
            fontWeight: 500,
            cursor: "pointer",
            fontFamily: "inherit",
          }}
        >
          全部启动
        </button>
        <button
          className="btn-ghost to-err"
          onClick={onStopAll}
          style={{
            flex: 1,
            borderRadius: 12,
            padding: 8,
            fontSize: 12,
            cursor: "pointer",
            fontFamily: "inherit",
          }}
        >
          全部停止
        </button>
      </div>
    </>
  );
}

/**
 * 面板外观。这里刻意不加 CSS 投影：窗口只比面板大一圈，
 * 投影会被窗口边界裁成一个硬边灰矩形。改用 macOS 的原生窗口投影。
 */
export const panelShell = {
  background: "var(--mbPanel)",
  backdropFilter: "var(--blur)",
  WebkitBackdropFilter: "var(--blur)",
  border: "1px solid var(--mbLine)",
  borderRadius: 20,
  boxShadow: "inset 0 1px 0 rgba(255,255,255,.25)",
  padding: 12,
  display: "flex",
  flexDirection: "column",
  gap: 10,
} as const;
