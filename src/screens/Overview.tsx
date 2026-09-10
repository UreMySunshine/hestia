import { UI } from "../data/icons";
import { areaPts, pts } from "../lib/format";
import { accents, serviceVM } from "../lib/vm";
import { EMPTY_FORM, type Store } from "../store";
import type { FilterLabel } from "../types";
import { LABEL } from "../data/seed";
import { Icon, Sparkline } from "../components/primitives";
import { ServiceCard, ServiceRow } from "../components/ServiceViews";

const FILTERS: FilterLabel[] = ["全部", "运行中", "已停止", "异常"];

export function Overview({ store }: { store: Store }) {
  const { state, patch, openDetail, toggleSvc, startAll, stopAll } = store;
  const { onGlass } = accents(state.theme);
  const S = state.services;
  const cores = state.cores;

  const runningCount = S.filter((s) => s.state === "running").length;
  const stoppedCount = S.filter((s) => s.state === "stopped").length;
  const errorCount = S.filter((s) => s.state === "error").length;
  const totalErrors = S.reduce((a, s) => a + s.errors, 0);
  const totalCpu = S.reduce((a, s) => a + s.cpu, 0);
  const totalMem = S.reduce((a, s) => a + s.mem, 0);

  const counts: Record<FilterLabel, number> = {
    全部: S.length,
    运行中: runningCount,
    已停止: stoppedCount,
    异常: errorCount,
  };

  const q = state.q.trim().toLowerCase();
  const cards = S.filter(
    (s) =>
      (!q ||
        s.name.toLowerCase().includes(q) ||
        s.cmd.toLowerCase().includes(q) ||
        s.proj.toLowerCase().includes(q)) &&
      (state.filter === "全部" || LABEL[s.state] === state.filter),
  );

  // totalCpu 是「占单核」的累加值，先折算成占整机的百分比再判高低。
  // 设计稿按「100 就是满」定的阈值，在多核机器上会把正常的并行构建误判为异常。
  const cpuOfMachine = totalCpu / cores;
  const score = Math.max(
    0,
    Math.round(
      100 -
        errorCount * 18 -
        totalErrors * 1.5 -
        Math.max(0, cpuOfMachine - 70) * 0.4,
    ),
  );
  const healthDot =
    score >= 85 ? "var(--ok)" : score >= 60 ? "var(--warn)" : "var(--err)";
  const healthState = score >= 85 ? "良好" : score >= 60 ? "需关注" : "异常";

  const healthSub = [
    {
      label: "运行中服务",
      value: `${runningCount}/${S.length}`,
      unit: "",
      color: "var(--ok)",
      rule: "transparent",
    },
    {
      label: "异常服务",
      value: String(errorCount),
      unit: "个",
      color: "var(--err)",
      rule: "var(--line2)",
    },
    {
      label: "累计重启",
      value: String(S.reduce((a, s) => a + s.restarts, 0)),
      unit: "次",
      color: "var(--tx)",
      rule: "var(--line2)",
    },
  ];

  const primaryStats = [
    {
      label: "总 CPU 占用",
      value: cpuOfMachine.toFixed(0),
      unit: "%",
      peak: `峰值 ${(Math.max(...state.gcpu) / cores).toFixed(0)}% · ${cores} 核`,
      color: "var(--ac)",
      series: state.gcpu,
      fill: "rgba(255,138,91,.16)",
    },
    {
      label: "总内存占用",
      value: (totalMem / 1024).toFixed(1),
      unit: "GB",
      peak: `${S.length} 个进程`,
      color: "var(--cy)",
      series: state.gmem,
      fill: "rgba(91,225,240,.14)",
    },
  ];

  const viewBtn = (
    active: boolean,
    path: string,
    label: string,
    onClick: () => void,
  ) => (
    <button
      onClick={onClick}
      aria-label={`${label}视图`}
      title={label}
      style={{
        width: 32,
        height: 25,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        border: "none",
        borderRadius: 10,
        cursor: "pointer",
        fontSize: 12,
        fontFamily: "inherit",
        background: active ? onGlass : "transparent",
        color: active ? "var(--tx)" : "var(--dim)",
      }}
    >
      <Icon d={path} size={15} />
    </button>
  );

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
          仪表盘
        </div>
      </div>

      <div
        style={{
          flex: 1,
          minHeight: 0,
          overflow: "hidden",
          padding: "0 6px",
          display: "flex",
          flexDirection: "column",
          gap: 14,
        }}
      >
        <div
          style={{
            flex: "none",
            display: "grid",
            gap: 12,
            padding: "2px 2px 0",
            gridTemplateColumns: "repeat(4,minmax(0,1fr))",
          }}
        >
          {/* 服务健康度 */}
          <div
            className="glass"
            style={{
              gridColumn: "span 2",
              border: "1px solid var(--line)",
              borderRadius: 20,
              padding: "18px 20px 16px",
              display: "flex",
              flexDirection: "column",
              boxShadow: "var(--shSm)",
            }}
          >
            <div
              style={{
                display: "flex",
                alignItems: "flex-start",
                justifyContent: "space-between",
                gap: 12,
              }}
            >
              <span
                style={{ fontSize: 12, color: "var(--mu)", letterSpacing: ".06em" }}
              >
                服务健康度
              </span>
              <span
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: 6,
                  fontSize: 11.5,
                  color: "var(--dim)",
                }}
              >
                <span
                  style={{
                    width: 7,
                    height: 7,
                    borderRadius: "50%",
                    background: healthDot,
                    boxShadow: `0 0 8px ${healthDot}`,
                  }}
                />
                {healthState}
              </span>
            </div>
            <div
              style={{
                display: "flex",
                alignItems: "baseline",
                gap: 5,
                marginTop: 14,
              }}
            >
              <span
                style={{
                  fontSize: 52,
                  fontWeight: 600,
                  letterSpacing: "-.045em",
                  lineHeight: 0.9,
                  color: healthDot,
                }}
              >
                {score}
              </span>
              <span style={{ fontSize: 15, color: "var(--dim)" }}>/ 100</span>
            </div>
            <div
              style={{
                marginTop: "auto",
                paddingTop: 20,
                display: "flex",
                alignItems: "stretch",
              }}
            >
              {healthSub.map((hs) => (
                <div
                  key={hs.label}
                  style={{
                    flex: 1,
                    minWidth: 0,
                    paddingLeft: 16,
                    borderLeft: `1px solid ${hs.rule}`,
                  }}
                >
                  <div
                    style={{ display: "flex", alignItems: "baseline", gap: 3 }}
                  >
                    <span
                      style={{
                        fontSize: 24,
                        fontWeight: 600,
                        letterSpacing: "-.03em",
                        lineHeight: 1,
                        color: hs.color,
                      }}
                    >
                      {hs.value}
                    </span>
                    <span style={{ fontSize: 11.5, color: "var(--dim)" }}>
                      {hs.unit}
                    </span>
                  </div>
                  <div
                    style={{
                      fontSize: 11.5,
                      color: "var(--mu)",
                      marginTop: 6,
                      overflow: "hidden",
                      textOverflow: "ellipsis",
                      whiteSpace: "nowrap",
                    }}
                  >
                    {hs.label}
                  </div>
                </div>
              ))}
            </div>
          </div>

          {/* 总 CPU / 总内存 */}
          {primaryStats.map((g) => {
            // 真实量级跨度大，按自身峰值归一
            const line = pts(g.series, 0, 100, 24);
            return (
              <div
                key={g.label}
                className="glass"
                style={{
                  border: "1px solid var(--line)",
                  borderRadius: 20,
                  display: "flex",
                  flexDirection: "column",
                  overflow: "hidden",
                  minHeight: 132,
                  boxShadow: "var(--shSm)",
                }}
              >
                <div
                  style={{
                    padding: "15px 17px 0",
                    display: "flex",
                    alignItems: "flex-start",
                    justifyContent: "space-between",
                    gap: 8,
                  }}
                >
                  <span
                    style={{
                      fontSize: 11.5,
                      color: "var(--mu)",
                      letterSpacing: ".04em",
                      overflow: "hidden",
                      textOverflow: "ellipsis",
                      whiteSpace: "nowrap",
                    }}
                  >
                    {g.label}
                  </span>
                  <span
                    style={{ fontSize: 11, color: "var(--dim)", flex: "none" }}
                  >
                    {g.peak}
                  </span>
                </div>
                <div
                  style={{
                    padding: "8px 17px 0",
                    display: "flex",
                    alignItems: "baseline",
                    gap: 4,
                  }}
                >
                  <span
                    style={{
                      fontSize: 33,
                      fontWeight: 600,
                      letterSpacing: "-.04em",
                      lineHeight: 1,
                      color: g.color,
                    }}
                  >
                    {g.value}
                  </span>
                  <span style={{ fontSize: 13, color: "var(--dim)" }}>
                    {g.unit}
                  </span>
                </div>
                <div style={{ height: 52, marginTop: "auto" }}>
                  <Sparkline
                    points={line}
                    area={areaPts(line, 100, 24)}
                    stroke={g.color}
                    fill={g.fill}
                    opacity={0.9}
                    style={{ width: "100%", height: "100%" }}
                  />
                </div>
              </div>
            );
          })}

        </div>

        <div
          style={{
            flex: "none",
            display: "flex",
            alignItems: "center",
            gap: 11,
            padding: "4px 2px 0",
          }}
        >
          <div style={{ fontSize: 16, fontWeight: 600 }}>服务总览</div>
          <div
            style={{
              display: "flex",
              background: "var(--sunk)",
              border: "1px solid var(--line2)",
              borderRadius: 13,
              padding: 3,
            }}
          >
            {viewBtn(state.view === "grid", UI.grid, "网格", () =>
              patch({ view: "grid" }),
            )}
            {viewBtn(state.view === "list", UI.list, "列表", () =>
              patch({ view: "list" }),
            )}
          </div>
        </div>

        <div
          style={{
            flex: "none",
            display: "flex",
            alignItems: "center",
            gap: 8,
            padding: "0 2px",
            minWidth: 0,
          }}
        >
          {FILTERS.map((f) => {
            const on = state.filter === f;
            return (
              <button
                key={f}
                onClick={() => patch({ filter: f })}
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
              flex: "0 1 220px",
              minWidth: 130,
            }}
          >
            <span style={{ color: "var(--dim)", display: "flex", flex: "none" }}>
              <Icon d={UI.search} size={14} />
            </span>
            <input
              value={state.q}
              onChange={(e) => patch({ q: e.target.value })}
              placeholder="搜索服务或命令"
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
          <div style={{ flex: "none", display: "flex", gap: 8 }}>
            <button
              className="btn-ghost to-cy"
              onClick={() =>
                patch({ screen: "new", formMode: "new", form: EMPTY_FORM })
              }
              title="新建服务"
              aria-label="新建服务"
              style={{
                width: 36,
                height: 34,
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                borderRadius: 13,
                cursor: "pointer",
                fontFamily: "inherit",
                boxShadow: "var(--shSm)",
              }}
            >
              <Icon d={UI.plus} sw={1.9} />
            </button>
            <button
              onClick={startAll}
              title="全部启动"
              aria-label="全部启动"
              style={{
                width: 36,
                height: 34,
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                border: "1px solid rgba(255,138,91,.55)",
                borderRadius: 13,
                background:
                  "linear-gradient(150deg,rgba(255,138,91,.5),rgba(255,138,91,.16))",
                color: "var(--onAc)",
                fontSize: 12,
                cursor: "pointer",
                fontFamily: "inherit",
                boxShadow: "var(--shSm)",
              }}
            >
              <Icon d={UI.play} sw={2} />
            </button>
            <button
              className="btn-ghost to-err"
              onClick={stopAll}
              title="全部停止"
              aria-label="全部停止"
              style={{
                width: 36,
                height: 34,
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                borderRadius: 13,
                fontSize: 11,
                cursor: "pointer",
                fontFamily: "inherit",
                boxShadow: "var(--shSm)",
              }}
            >
              <Icon d={UI.stop} sw={1.7} />
            </button>
          </div>
        </div>

        <div
          style={{
            flex: 1,
            minHeight: 0,
            overflowY: "auto",
            overflowX: "hidden",
            padding: "0 0 20px",
            scrollbarGutter: "stable",
          }}
        >
          {state.ready && S.length === 0 ? (
            <button
              className="glass2 dashed-card"
              onClick={() =>
                patch({ screen: "new", formMode: "new", form: EMPTY_FORM })
              }
              style={{
                width: "100%",
                borderRadius: 22,
                padding: "44px 24px",
                display: "flex",
                flexDirection: "column",
                alignItems: "center",
                gap: 10,
                color: "var(--dim)",
                cursor: "pointer",
                fontFamily: "inherit",
              }}
            >
              <Icon d={UI.plus} size={22} sw={1.6} />
              <div style={{ fontSize: 14, color: "var(--mu)" }}>
                还没有任何服务
              </div>
              <div style={{ fontSize: 12.5 }}>点击这里保存第一条启动命令</div>
            </button>
          ) : state.view === "list" ? (
            <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
              {cards.map((s) => (
                <ServiceRow
                  key={s.id}
                  svc={s}
                  vm={serviceVM(s)}
                  onOpen={() => openDetail(s.id)}
                  onToggle={() => toggleSvc(s)}
                />
              ))}
            </div>
          ) : (
            <div
              style={{
                display: "grid",
                gap: 14,
                gridTemplateColumns:
                  "repeat(auto-fill,minmax(min(320px,100%),1fr))",
              }}
            >
              {cards.map((s) => (
                <ServiceCard
                  key={s.id}
                  svc={s}
                  vm={serviceVM(s)}
                  onOpen={() => openDetail(s.id)}
                  onToggle={() => toggleSvc(s)}
                />
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
