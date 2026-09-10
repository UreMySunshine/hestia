import { useLayoutEffect, useRef, useState } from "react";
import appIcon from "../assets/app-icon.png";
import { LABEL } from "../data/seed";
import { UI } from "../data/icons";
import { serviceVM, type ServiceVM } from "../lib/vm";
import type { Store } from "../store";
import type { FilterLabel, MonitorSort, Service } from "../types";
import { Icon, Sparkline } from "../components/primitives";

/**
 * 两套布局。
 *
 * 设计稿按 1440 宽绘制，表格用固定列宽，九列合计 1254；而窗口最小 1100、
 * 内容区只有约 810，一行塞不下。宽度够时仍然是一行一条的表格，
 * 不够时改成分行卡片：第一行身份、第二行资源、第三行其余指标，
 * 两种形态都不出现横向滚动。
 *
 * 列的取舍：运行时长和重启次数在仪表盘的服务卡片里已经有了，这里不再重复，
 * 换成只有持续采样才拿得到的量——CPU / 内存的窗口峰值和放大后的趋势曲线。
 */
// 阈值仍是 880：窗口最小 1100 时内容区约 820，落在分行卡片一侧。
// 减到七列后表格在 820 也塞得下，但你上次明确要过窗口小的时候用分行形式，所以保持不变。
const WIDE_AT = 880;

const GRID =
  "minmax(130px,1.6fr) 68px 82px 90px minmax(140px,1.9fr) 62px minmax(70px,1fr)";

const COLS = ["服务", "状态", "CPU", "内存", "趋势", "端口", "错误"];

const FILTERS: FilterLabel[] = ["全部", "运行中", "已停止", "异常"];
const SORTS: MonitorSort[] = ["默认", "CPU", "内存", "名称"];

const cell = {
  minWidth: 0,
  overflow: "hidden",
  textOverflow: "ellipsis",
  whiteSpace: "nowrap",
} as const;

function Identity({
  svc,
  vm,
  isSelf,
  iconSize,
}: {
  svc: Service;
  vm: ServiceVM;
  isSelf: boolean;
  iconSize: number;
}) {
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 10, minWidth: 0 }}>
      {/* Hestia 自身这一行用真正的应用图标，和 Dock、侧栏保持一致 */}
      {isSelf ? (
        <img
          src={appIcon}
          alt=""
          style={{
            width: iconSize,
            height: iconSize,
            flex: "none",
            borderRadius: 9,
            objectFit: "cover",
            border: `1px solid ${vm.iconBd}`,
          }}
        />
      ) : (
        <span
          style={{
            width: iconSize,
            height: iconSize,
            flex: "none",
            borderRadius: 9,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            background: vm.iconBg,
            border: `1px solid ${vm.iconBd}`,
            color: vm.iconTx,
          }}
        >
          <Icon d={vm.iconPath} size={iconSize / 2 + 1} />
        </span>
      )}
      <div style={{ minWidth: 0 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 7 }}>
          <span style={cell}>{svc.name}</span>
          {isSelf && (
            <span
              style={{
                flex: "none",
                fontSize: 10,
                color: "var(--cy)",
                border: "1px solid rgba(91,225,240,.4)",
                borderRadius: 8,
                padding: "1px 6px",
              }}
            >
              自身
            </span>
          )}
        </div>
      </div>
    </div>
  );
}

function StateDot({ vm }: { vm: ServiceVM }) {
  return (
    <div
      style={{
        ...cell,
        display: "flex",
        alignItems: "center",
        gap: 6,
        fontSize: 11.5,
        color: vm.pillTx,
      }}
    >
      <span
        style={{
          width: 6,
          height: 6,
          flex: "none",
          borderRadius: "50%",
          background: vm.dot,
          animation: vm.pulse,
        }}
      />
      {vm.stateLabel}
    </div>
  );
}

/**
 * 当前值 + 窗口峰值。
 *
 * 原设计在数值旁边还有一条占比条，已经去掉：CPU 那条的分母是整机核数，
 * 内存那条的分母却是写死的 1600MB，同一行两个刻度，而且内存超过 1.6G 就一律顶格，
 * 4669M 和 8362M 画出来一模一样。数值、峰值和趋势曲线已经把量级说清楚了。
 */
function Meter({
  label,
  value,
  color,
  peak,
}: {
  label?: string;
  value: string;
  color?: string;
  peak: string;
}) {
  return (
    <div style={{ minWidth: 0 }}>
      <div
        style={{ display: "flex", alignItems: "baseline", gap: 7, minWidth: 0 }}
      >
        {label && (
          <span style={{ flex: "none", fontSize: 11, color: "var(--dim)" }}>
            {label}
          </span>
        )}
        <span style={{ ...cell, fontSize: 12.5, color }}>{value}</span>
      </div>
      <div style={{ ...cell, fontSize: 10.5, color: "var(--dim)", marginTop: 4 }}>
        峰值 {peak}
      </div>
    </div>
  );
}

export function Monitor({ store }: { store: Store }) {
  const { state, patch, openDetail } = store;
  const S = state.services;
  const cores = state.cores;
  const box = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(0);

  useLayoutEffect(() => {
    const el = box.current;
    if (!el) return;
    const ro = new ResizeObserver(([e]) => setWidth(e.contentRect.width));
    ro.observe(el);
    setWidth(el.clientWidth);
    return () => ro.disconnect();
  }, []);

  // 首帧还没量到宽度，先按宽版渲染，避免闪一下窄版
  const wide = width === 0 || width >= WIDE_AT;

  const selfRow: Service = {
    id: "__self",
    name: "Hestia",
    proj: "应用自身",
    ic: "pulse",
    cmd: "",
    stop: "",
    cwd: "",
    port: 0,
    autoRestart: false,
    state: "running",
    cpu: state.self.cpu,
    mem: state.self.mem,
    up: state.self.up,
    restarts: 0,
    errors: 0,
    portOpen: false,
    ports: [],
    lastError: "",
    pid: state.self.pid,
    env: [],
    hist: state.self.hist,
    mhist: state.self.hist,
  };

  const rows = [...S, selfRow];

  const counts: Record<FilterLabel, number> = {
    全部: rows.length,
    运行中: rows.filter((s) => s.state === "running").length,
    已停止: rows.filter((s) => s.state === "stopped").length,
    异常: rows.filter((s) => s.state === "error").length,
  };

  const q = state.monQ.trim().toLowerCase();
  const shown = rows.filter(
    (s) =>
      (state.monFilter === "全部" || LABEL[s.state] === state.monFilter) &&
      (!q ||
        s.name.toLowerCase().includes(q) ||
        s.proj.toLowerCase().includes(q) ||
        [s.port, ...s.ports].some((n) => n > 0 && String(n).includes(q))),
  );
  // filter 已经产出新数组，就地排序不会动到 state
  if (state.monSort === "CPU") shown.sort((a, b) => b.cpu - a.cpu);
  else if (state.monSort === "内存") shown.sort((a, b) => b.mem - a.mem);
  else if (state.monSort === "名称")
    shown.sort((a, b) => a.name.localeCompare(b.name, "zh"));

  const narrowed = shown.length !== rows.length;

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
      <div style={{ flex: "none", padding: "2px 4px 0" }}>
        <div style={{ fontSize: 25, fontWeight: 600, letterSpacing: "-.02em" }}>
          监控面板
        </div>
        <div style={{ fontSize: 13, color: "var(--mu)", marginTop: 6 }}>
          每 1.4 秒采样一次 · 曲线与峰值覆盖最近 56 秒 · 含 Hestia 自身 ·{" "}
          {narrowed
            ? `筛选出 ${shown.length} / ${rows.length} 个进程`
            : `共 ${rows.length} 个进程`}
        </div>
      </div>

      <div
        style={{
          flex: "none",
          display: "flex",
          alignItems: "center",
          gap: 8,
          rowGap: 9,
          flexWrap: "wrap",
          padding: "0 6px",
        }}
      >
        {FILTERS.map((f) => {
          const on = state.monFilter === f;
          return (
            <button
              key={f}
              onClick={() => patch({ monFilter: f })}
              style={{
                flex: "none",
                padding: "7px 15px",
                fontSize: 12.5,
                cursor: "pointer",
                fontFamily: "inherit",
                borderRadius: 13,
                fontWeight: on ? 600 : 400,
                background: on
                  ? "linear-gradient(150deg,rgba(255,138,91,.45),rgba(255,138,91,.14))"
                  : "var(--glass)",
                border: `1px solid ${on ? "rgba(255,138,91,.5)" : "var(--line2)"}`,
                color: on ? "var(--tx)" : "var(--mu)",
                boxShadow: on ? "var(--shSm)" : "none",
              }}
            >
              {f} <span style={{ opacity: 0.6 }}>{counts[f]}</span>
            </button>
          );
        })}

        <span style={{ flex: 1, minWidth: 8 }} />

        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: 9,
            background: "var(--sunk)",
            border: "1px solid var(--line2)",
            borderRadius: 14,
            padding: "8px 14px",
            flex: "0 1 200px",
            minWidth: 130,
          }}
        >
          <span style={{ color: "var(--dim)", display: "flex", flex: "none" }}>
            <Icon d={UI.search} size={14} />
          </span>
          <input
            value={state.monQ}
            onChange={(e) => patch({ monQ: e.target.value })}
            placeholder="搜索服务或端口"
            style={{
              flex: 1,
              minWidth: 0,
              background: "transparent",
              border: "none",
              outline: "none",
              color: "var(--tx)",
              fontSize: 12.5,
              fontFamily: "inherit",
            }}
          />
        </div>

        <div
          style={{
            flex: "none",
            display: "flex",
            alignItems: "center",
            gap: 3,
            background: "var(--sunk)",
            border: "1px solid var(--line2)",
            borderRadius: 14,
            padding: 3,
          }}
        >
          {SORTS.map((k) => {
            const on = state.monSort === k;
            return (
              <button
                key={k}
                onClick={() => patch({ monSort: k })}
                title={k === "默认" ? "按配置顺序" : `按${k}从高到低`}
                style={{
                  padding: "5px 11px",
                  fontSize: 12,
                  cursor: "pointer",
                  fontFamily: "inherit",
                  borderRadius: 11,
                  border: "1px solid transparent",
                  background: on ? "var(--glass)" : "transparent",
                  borderColor: on ? "var(--line2)" : "transparent",
                  color: on ? "var(--tx)" : "var(--dim)",
                }}
              >
                {k}
              </button>
            );
          })}
        </div>
      </div>

      <div
        ref={box}
        style={{
          flex: 1,
          overflowY: "auto",
          overflowX: "hidden",
          padding: "2px 6px 20px",
          display: "flex",
          flexDirection: "column",
          gap: 12,
          scrollbarGutter: "stable",
        }}
      >
        <div
          className="glass"
          style={{
            border: "1px solid var(--line2)",
            borderRadius: 22,
            padding: "8px 10px",
            flex: "none",
            minWidth: 0,
            boxShadow: "var(--sh)",
          }}
        >
          {wide && (
            <div
              style={{
                display: "grid",
                gridTemplateColumns: GRID,
                alignItems: "center",
                gap: 9,
                padding: "11px 13px",
                fontSize: 11,
                color: "var(--dim)",
                letterSpacing: ".08em",
              }}
            >
              {COLS.map((c) => (
                <div key={c} style={cell}>
                  {c}
                </div>
              ))}
            </div>
          )}

          {shown.length === 0 && (
            <div
              style={{
                padding: "34px 13px",
                textAlign: "center",
                fontSize: 12.5,
                color: "var(--dim)",
              }}
            >
              没有符合条件的进程
            </div>
          )}

          {shown.map((s) => {
            const v = serviceVM(s, cores);
            const isSelf = s.id === "__self";
            const showSpark = !state.prefs.quiet || s.state === "running";
            // 列宽只有 70px 起，直接铺错误原文会被截断成看不出内容的一截，
            // 所以显示累计条数，原文放 title 里悬停可见，详情页有完整日志
            const errText = s.errors ? `${s.errors} 条` : "无";
            const onOpen = () => !isSelf && openDetail(s.id);

            if (wide) {
              return (
                <div
                  key={s.id}
                  className={`mrow${isSelf ? " is-self" : ""}`}
                  onClick={onOpen}
                  style={{
                    display: "grid",
                    gridTemplateColumns: GRID,
                    alignItems: "center",
                    gap: 9,
                    padding: "10px 13px",
                    borderRadius: 15,
                    fontSize: 12.5,
                    cursor: "pointer",
                  }}
                >
                  <Identity svc={s} vm={v} isSelf={isSelf} iconSize={26} />
                  <StateDot vm={v} />
                  <Meter
                    value={`${v.cpu}%`}
                    color={v.cpuColor}
                    peak={`${v.peakCpu}%`}
                  />
                  <Meter
                    value={`${v.mem}M`}
                    peak={`${v.peakMem}M`}
                  />
                  <div style={{ height: 40, minWidth: 0 }}>
                    {showSpark && (
                      <Sparkline
                        points={v.spark}
                        area={v.sparkArea}
                        stroke={v.line}
                        fill={v.fill}
                        strokeWidth={1.6}
                        style={{ width: "100%", height: "100%" }}
                      />
                    )}
                  </div>
                  <div
                    style={{
                      ...cell,
                      fontFamily: "JetBrains Mono,monospace",
                      fontSize: 11.5,
                      color: v.portDrift ? "var(--warn)" : "var(--mu)",
                    }}
                    title={
                      v.portDrift ? `配置为 ${s.port}，实际监听 ${v.port}` : undefined
                    }
                  >
                    {v.port ? v.port : "—"}
                  </div>
                  <div
                    style={{
                      ...cell,
                      fontSize: 11.5,
                      color: s.errors ? "var(--err)" : "var(--dim)",
                    }}
                    title={s.lastError || undefined}
                  >
                    {errText}
                  </div>
                </div>
              );
            }

            // 窄版：一条记录拆成三行
            return (
              <div
                key={s.id}
                className={`mrow${isSelf ? " is-self" : ""}`}
                onClick={onOpen}
                style={{
                  display: "flex",
                  flexDirection: "column",
                  gap: 9,
                  padding: "12px 13px",
                  borderRadius: 15,
                  fontSize: 12.5,
                  cursor: "pointer",
                }}
              >
                <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
                  <Identity svc={s} vm={v} isSelf={isSelf} iconSize={30} />
                  <span style={{ flex: 1 }} />
                  <StateDot vm={v} />
                </div>

                <div
                  style={{
                    display: "grid",
                    gridTemplateColumns: "repeat(auto-fit,minmax(150px,1fr))",
                    alignItems: "center",
                    gap: "8px 14px",
                  }}
                >
                  <Meter
                    label="CPU"
                    value={`${v.cpu}%`}
                    color={v.cpuColor}
                    peak={`${v.peakCpu}%`}
                  />
                  <Meter
                    label="内存"
                    value={`${v.mem}M`}
                    peak={`${v.peakMem}M`}
                  />
                  <div style={{ height: 36, minWidth: 0 }}>
                    {showSpark && (
                      <Sparkline
                        points={v.spark}
                        area={v.sparkArea}
                        stroke={v.line}
                        fill={v.fill}
                        strokeWidth={1.6}
                        style={{ width: "100%", height: "100%" }}
                      />
                    )}
                  </div>
                </div>

                <div
                  style={{
                    display: "flex",
                    alignItems: "center",
                    gap: 10,
                    flexWrap: "wrap",
                    fontSize: 11.5,
                    color: "var(--dim)",
                  }}
                >
                  <span
                    style={{ color: v.portDrift ? "var(--warn)" : undefined }}
                    title={
                      v.portDrift ? `配置为 ${s.port}，实际监听 ${v.port}` : undefined
                    }
                  >
                    端口 {v.port ? v.port : "—"}
                  </span>
                  <span>·</span>
                  <span
                    style={{ color: s.errors ? "var(--err)" : "var(--dim)", ...cell }}
                    title={s.lastError || undefined}
                  >
                    {errText}
                  </span>
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}
