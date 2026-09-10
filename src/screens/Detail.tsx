import { memo, useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import { UI } from "../data/icons";
import { areaPts, fmtUp, hhmmss, pts } from "../lib/format";
import { accents, serviceVM } from "../lib/vm";
import { configToForm, type Store } from "../store";
import type { LogLine, LogMode } from "../types";
import { Icon, Sparkline } from "../components/primitives";

const LVL_COLOR: Record<string, string> = {
  ERROR: "var(--err)",
  WARN: "var(--warn)",
  INFO: "var(--dim)",
};

/**
 * 单行日志。做成独立的 memo 组件，日志成批到达时只有新增的行会渲染，
 * 已有的几百行不再参与协调。
 *
 * 这里刻意不加入场动画：设计稿原本每行带 `fadeUp`，但本项目实测过——
 * 只要有 CSS 动画在跑，WebKit 就会持续合成整个窗口（空载 8.6% vs 暂停 1.5%）。
 * 日志持续流入时新行不断挂载，动画等于一直在跑；打开面板的瞬间更是
 * 几百个动画同时触发。
 */
const LogRow = memo(function LogRow({ line }: { line: LogLine }) {
  return (
    <div style={{ display: "flex", gap: 9, padding: "1px 10px" }}>
      <span style={{ color: "var(--dim)", flex: "none" }}>{hhmmss(line.ts)}</span>
      <span
        style={{
          flex: "none",
          width: 36,
          color: LVL_COLOR[line.lvl] ?? "var(--dim)",
        }}
      >
        {line.lvl}
      </span>
      <span style={{ color: "var(--mu)", wordBreak: "break-word" }}>
        {line.txt}
      </span>
    </div>
  );
});

const LOG_TABS: { k: LogMode; l: string }[] = [
  { k: "THIS", l: "本服务" },
  { k: "ERR", l: "仅错误" },
  { k: "ALL", l: "全部" },
];

export function Detail({ store }: { store: Store }) {
  const { state, patch, selected, toggleSvc, restartSvc, clearLogs } = store;
  const { onGlass } = accents(state.theme);
  const sel = selected;
  const logEl = useRef<HTMLDivElement>(null);

  const logs = useMemo(
    () =>
      state.logs
        .filter((l) =>
          state.logMode === "ALL"
            ? true
            : state.logMode === "ERR"
              ? l.lvl === "ERROR" || l.lvl === "WARN"
              : l.sid === sel?.id,
        )
        .slice(-300),
    [state.logs, state.logMode, sel?.id],
  );

  useEffect(() => {
    if (!sel) patch({ screen: "overview" });
  }, [sel, patch]);

  // 抽屉展开时先只画外壳，日志行推迟一帧再挂。
  // 300 行 × 4 个节点，和抽屉自身 backdrop-filter 的首次合成，原来落在同一帧里，
  // 点击到面板出现之间有肉眼可见的停顿。拆成两帧后面板立刻出现，行随后补上。
  const [rowsReady, setRowsReady] = useState(false);
  useEffect(() => {
    if (!state.drawerOpen) {
      setRowsReady(false);
      return;
    }
    const id = requestAnimationFrame(() => setRowsReady(true));
    return () => cancelAnimationFrame(id);
  }, [state.drawerOpen]);

  // 依赖里必须有 drawerOpen 和 rowsReady：打开面板时这两个值才是变化的那一个，
  // 原来只依赖 follow 和 logs.length，打开瞬间两者都没变，所以自动滚动不触发。
  // 用 useLayoutEffect 是为了在绘制前就压到底，否则会先看见顶部再跳一下。
  useLayoutEffect(() => {
    if (state.follow && state.drawerOpen && rowsReady && logEl.current)
      logEl.current.scrollTop = logEl.current.scrollHeight;
  }, [state.follow, state.drawerOpen, rowsReady, logs.length]);

  if (!sel) return null;

  const d = serviceVM(sel);
  const cpuLine = pts(sel.hist, 100, 200, 56);
  // 内存量级随服务差别很大，按自身峰值归一才看得出趋势
  const memLine = pts(sel.mhist, 0, 200, 56);

  const stats = [
    {
      label: "状态",
      value: d.stateLabel,
      hint:
        sel.state === "running"
          ? `PID ${sel.pid}`
          : sel.lastError || "未运行",
      color: d.pillTx,
    },
    {
      label: "运行时长",
      value: fmtUp(sel.up),
      hint: `重启 ${sel.restarts} 次`,
      color: "var(--tx)",
    },
    {
      label: "端口",
      value: d.port ? String(d.port) : "—",
      hint: d.portDrift
        ? `配置为 ${sel.port}`
        : sel.ports.length
          ? "自动探测"
          : sel.port
            ? "未监听"
            : "无监听端口",
      color: d.portDrift ? "var(--warn)" : "var(--cy)",
    },
    {
      label: "错误计数",
      value: String(sel.errors),
      hint: "最近 1 小时",
      color: sel.errors ? "var(--err)" : "var(--tx)",
    },
  ];

  const headBtn = {
    width: 38,
    height: 36,
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    borderRadius: 13,
    cursor: "pointer",
    fontFamily: "inherit",
  } as const;

  const card = {
    border: "1px solid var(--line2)",
    borderRadius: 20,
    padding: "17px 18px",
    display: "flex",
    flexDirection: "column",
    flex: "none",
    boxShadow: "var(--shSm)",
  } as const;

  return (
    <div
      style={{
        flex: 1,
        display: "flex",
        flexDirection: "column",
        minWidth: 0,
        gap: 14,
      }}
    >
      <div
        style={{
          flex: "none",
          height: 58,
          display: "flex",
          alignItems: "center",
          gap: 12,
          padding: "2px 4px 0",
        }}
      >
        <button
          onClick={() => patch({ screen: "overview" })}
          title="返回"
          aria-label="返回"
          style={{
            width: 34,
            height: 32,
            border: "1px solid var(--line)",
            borderRadius: 12,
            background: "var(--glass)",
            color: "var(--mu)",
            cursor: "pointer",
            fontFamily: "inherit",
            fontSize: 14,
          }}
        >
          <Icon d={UI.back} size={15} sw={1.9} />
        </button>
        <div
          style={{
            width: 46,
            height: 46,
            flex: "none",
            borderRadius: 16,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            background: d.iconBg,
            border: `1px solid ${d.iconBd}`,
            color: d.iconTx,
          }}
        >
          <Icon d={d.iconPath} size={23} sw={1.7} />
        </div>
        <div style={{ minWidth: 0 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
            <div
              style={{ fontSize: 22, fontWeight: 600, letterSpacing: "-.02em" }}
            >
              {sel.name}
            </div>
            <div
              style={{
                display: "flex",
                alignItems: "center",
                gap: 6,
                padding: "3px 10px",
                borderRadius: 11,
                fontSize: 10.5,
                fontWeight: 500,
                background: d.pillBg,
                border: `1px solid ${d.pillBd}`,
                color: d.pillTx,
              }}
            >
              <span
                style={{
                  width: 5,
                  height: 5,
                  borderRadius: "50%",
                  background: d.dot,
                  animation: d.pulse,
                }}
              />
              {d.stateLabel}
            </div>
          </div>
          <div
            style={{
              fontSize: 11.5,
              color: "var(--dim)",
              marginTop: 5,
              overflow: "hidden",
              textOverflow: "ellipsis",
              whiteSpace: "nowrap",
            }}
          >
            {d.metaLine}
          </div>
        </div>
        <span style={{ flex: 1 }} />

        <button
          onClick={() => toggleSvc(sel)}
          title={d.btnLabel}
          aria-label={d.btnLabel}
          style={{
            ...headBtn,
            fontSize: 12,
            background: d.btnBg,
            border: `1px solid ${d.btnBd}`,
            color: d.btnTx,
          }}
        >
          <Icon d={d.btnPath} size={17} sw={1.9} />
        </button>
        <button
          className="btn-ghost to-cy"
          onClick={() =>
            patch({ screen: "new", formMode: "edit", form: configToForm(sel) })
          }
          title="编辑配置"
          aria-label="编辑配置"
          style={{ ...headBtn, flex: "none" }}
        >
          <Icon d={UI.edit} size={15} />
        </button>
        <button
          className="btn-ghost to-cy-tx"
          onClick={() => restartSvc(sel.id)}
          title="重启"
          aria-label="重启"
          style={{ ...headBtn, fontSize: 14 }}
        >
          <Icon d={UI.restart} size={15} />
        </button>
        <button
          onClick={() => patch((s) => ({ drawerOpen: !s.drawerOpen }))}
          title={state.drawerOpen ? "关闭日志" : "打开日志"}
          aria-label={state.drawerOpen ? "关闭日志" : "打开日志"}
          style={{
            ...headBtn,
            fontSize: 13,
            background: state.drawerOpen ? onGlass : "var(--glass)",
            border: `1px solid ${state.drawerOpen ? "rgba(91,225,240,.5)" : "var(--line)"}`,
            color: state.drawerOpen ? "var(--cy)" : "var(--mu)",
          }}
        >
          <Icon d={UI.panel} size={15} />
        </button>
      </div>

      <div style={{ flex: 1, display: "flex", minHeight: 0, position: "relative" }}>
        <div
          style={{
            flex: 1,
            overflowY: "auto",
            overflowX: "hidden",
            padding: "2px 6px 20px",
            display: "flex",
            flexDirection: "column",
            gap: 12,
            minWidth: 0,
            scrollbarGutter: "stable",
          }}
        >
          <div
            style={{
              display: "grid",
              gridTemplateColumns: "repeat(auto-fit,minmax(min(150px,100%),1fr))",
              gap: 12,
              flex: "none",
            }}
          >
            {stats.map((st) => (
              <div
                key={st.label}
                className="glass"
                style={{
                  border: "1px solid var(--line2)",
                  borderRadius: 18,
                  padding: "15px 16px",
                  display: "flex",
                  flexDirection: "column",
                  gap: 5,
                  boxShadow: "var(--shSm)",
                }}
              >
                <div
                  style={{
                    fontSize: 11,
                    color: "var(--dim)",
                    letterSpacing: ".08em",
                  }}
                >
                  {st.label}
                </div>
                <div
                  style={{
                    fontSize: 21,
                    fontWeight: 600,
                    letterSpacing: "-.02em",
                    color: st.color,
                  }}
                >
                  {st.value}
                </div>
                <div style={{ fontSize: 11, color: "var(--dim)" }}>{st.hint}</div>
              </div>
            ))}
          </div>

          <div
            style={{
              display: "grid",
              gridTemplateColumns: "repeat(auto-fit,minmax(min(220px,100%),1fr))",
              gap: 12,
              flex: "none",
            }}
          >
            {[
              {
                label: "CPU 占用",
                value: `${d.cpu}%`,
                color: "var(--ac)",
                stroke: "#FF8A5B",
                fill: "rgba(255,138,91,.18)",
                line: cpuLine,
              },
              {
                label: "内存占用",
                value: `${d.mem} MB`,
                color: "var(--cy)",
                stroke: "#5BE1F0",
                fill: "rgba(91,225,240,.16)",
                line: memLine,
              },
            ].map((c) => (
              <div
                key={c.label}
                className="glass"
                style={{
                  border: "1px solid var(--line2)",
                  borderRadius: 20,
                  padding: "15px 17px",
                  boxShadow: "var(--shSm)",
                }}
              >
                <div
                  style={{
                    display: "flex",
                    justifyContent: "space-between",
                    alignItems: "baseline",
                    marginBottom: 9,
                  }}
                >
                  <span
                    style={{
                      fontSize: 12,
                      color: "var(--dim)",
                      letterSpacing: ".06em",
                    }}
                  >
                    {c.label}
                  </span>
                  <span
                    style={{ fontSize: 14, fontWeight: 600, color: c.color }}
                  >
                    {c.value}
                  </span>
                </div>
                <Sparkline
                  viewBox="0 0 200 56"
                  points={c.line}
                  area={areaPts(c.line, 200, 56)}
                  stroke={c.stroke}
                  fill={c.fill}
                  strokeWidth={2.2}
                  style={{ width: "100%", height: 74 }}
                />
              </div>
            ))}
          </div>

          <div className="glass" style={{ ...card, gap: 13 }}>
            <div style={{ fontSize: 14, fontWeight: 600 }}>启动与停止命令</div>
            <div style={{ display: "flex", gap: 13, alignItems: "center" }}>
              <div
                style={{ width: 56, flex: "none", fontSize: 11.5, color: "var(--dim)" }}
              >
                目录
              </div>
              <div
                style={{
                  fontFamily: "JetBrains Mono,monospace",
                  fontSize: 12,
                  color: "var(--mu)",
                }}
              >
                {sel.cwd}
              </div>
            </div>
            {[
              { k: "启动", v: sel.cmd, color: "var(--ac)" },
              { k: "停止", v: sel.stop, color: "var(--err)" },
            ].map((r) => (
              <div
                key={r.k}
                style={{ display: "flex", gap: 13, alignItems: "center" }}
              >
                <div
                  style={{
                    width: 56,
                    flex: "none",
                    fontSize: 11.5,
                    color: r.color,
                    fontWeight: 500,
                  }}
                >
                  {r.k}
                </div>
                <div
                  style={{
                    flex: 1,
                    minWidth: 0,
                    fontFamily: "JetBrains Mono,monospace",
                    fontSize: 12,
                    background: "var(--sunk)",
                    border: "1px solid var(--line2)",
                    borderLeft: `2px solid ${r.color}`,
                    borderRadius: 12,
                    padding: "10px 13px",
                    overflow: "hidden",
                    textOverflow: "ellipsis",
                    whiteSpace: "nowrap",
                  }}
                >
                  {r.v}
                </div>
              </div>
            ))}
          </div>

          <div className="glass" style={{ ...card, gap: 11 }}>
            <div style={{ fontSize: 14, fontWeight: 600 }}>环境变量</div>
            {sel.env.map((e) => (
              <div
                key={e.k}
                style={{
                  display: "flex",
                  gap: 16,
                  fontFamily: "JetBrains Mono,monospace",
                  fontSize: 12,
                }}
              >
                <div style={{ width: 200, color: "var(--cy)", flex: "none" }}>
                  {e.k}
                </div>
                <div
                  style={{
                    color: "var(--mu)",
                    overflow: "hidden",
                    textOverflow: "ellipsis",
                    whiteSpace: "nowrap",
                  }}
                >
                  {e.v}
                </div>
              </div>
            ))}
          </div>
        </div>

        {state.drawerOpen && (
          <div
            style={{
              position: "absolute",
              top: 0,
              right: 0,
              bottom: 0,
              width: "min(420px,60%)",
              zIndex: 5,
              background: "var(--drawer)",
              backdropFilter: "var(--blur)",
              WebkitBackdropFilter: "var(--blur)",
              border: "1px solid var(--line)",
              borderRadius: 22,
              boxShadow: "var(--sh)",
              display: "flex",
              flexDirection: "column",
              minHeight: 0,
              overflow: "hidden",
            }}
          >
            <div
              style={{
                flex: "none",
                padding: "14px 16px 10px",
                display: "flex",
                alignItems: "center",
                gap: 9,
              }}
            >
              <span
                style={{
                  width: 7,
                  height: 7,
                  borderRadius: "50%",
                  background: "var(--ok)",
                  boxShadow: "0 0 10px var(--ok)",
                }}
              />
              <div style={{ fontSize: 13.5, fontWeight: 600 }}>实时日志</div>
              <span style={{ flex: 1 }} />
              {LOG_TABS.map((t) => {
                const on = state.logMode === t.k;
                return (
                  <button
                    key={t.k}
                    onClick={() => patch({ logMode: t.k })}
                    style={{
                      padding: "4px 10px",
                      borderRadius: 10,
                      fontSize: 11,
                      cursor: "pointer",
                      fontFamily: "inherit",
                      background: on ? onGlass : "transparent",
                      border: `1px solid ${on ? "var(--line)" : "var(--line2)"}`,
                      color: on ? "var(--tx)" : "var(--dim)",
                    }}
                  >
                    {t.l}
                  </button>
                );
              })}
            </div>

            <div
              ref={logEl}
              style={{
                flex: 1,
                overflowY: "auto",
                margin: "0 12px",
                padding: "10px 4px",
                background: "var(--sunk)",
                border: "1px solid var(--line2)",
                borderRadius: 16,
                fontFamily: "JetBrains Mono,monospace",
                fontSize: 11,
                lineHeight: 1.75,
              }}
            >
              {rowsReady &&
                logs.map((l) => <LogRow key={l.id} line={l} />)}
            </div>

            <div
              style={{
                flex: "none",
                padding: "10px 16px 14px",
                display: "flex",
                alignItems: "center",
                gap: 11,
                fontSize: 11,
                color: "var(--dim)",
              }}
            >
              <button
                onClick={() => patch((s) => ({ follow: !s.follow }))}
                style={{
                  borderRadius: 10,
                  padding: "5px 11px",
                  fontSize: 11,
                  cursor: "pointer",
                  fontFamily: "inherit",
                  background: state.follow ? onGlass : "transparent",
                  border: `1px solid ${state.follow ? "var(--line)" : "var(--line2)"}`,
                  color: state.follow ? "var(--ok)" : "var(--dim)",
                }}
              >
                {state.follow ? "自动滚动 开" : "自动滚动 关"}
              </button>
              <span>{logs.length} 行</span>
              <span style={{ flex: 1 }} />
              <button
                className="link-dim to-err"
                onClick={clearLogs}
                style={{ fontSize: 11, cursor: "pointer", fontFamily: "inherit" }}
              >
                清空
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
