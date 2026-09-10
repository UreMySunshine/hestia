import { UI } from "../data/icons";
import { PREF_ITEMS, SHORTCUTS } from "../data/seed";
import { accents } from "../lib/vm";
import { configToForm, type Store } from "../store";
import { Icon, Toggle } from "../components/primitives";

/** 与 Rust 侧 LOG_CAP 保持一致 */
const LOG_CAP = 4000;

export function Settings({ store }: { store: Store }) {
  const { state, patch, togglePref, saveService } = store;
  const { onGlass, selBd, selTx } = accents(state.theme);
  const S = state.services;
  const cur = S.find((s) => s.id === state.envSel) || S[0];
  const envRows = cur?.env ?? [];

  const logPrefs = [
    {
      label: "日志缓冲上限",
      value: `${LOG_CAP.toLocaleString()} 行`,
      bar: "100%",
    },
    {
      label: "当前缓冲",
      value: `${state.logs.length.toLocaleString()} 行`,
      bar: `${Math.min(100, (state.logs.length / LOG_CAP) * 100).toFixed(0)}%`,
    },
  ];

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
          padding: "2px 4px 0",
        }}
      >
        <div style={{ fontSize: 25, fontWeight: 600, letterSpacing: "-.02em" }}>
          设置
        </div>
      </div>

      <div
        style={{
          flex: 1,
          minHeight: 0,
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
            border: "1px solid var(--line)",
            borderRadius: 20,
            padding: "4px 18px",
            flex: "none",
            boxShadow: "var(--shSm)",
          }}
        >
          {PREF_ITEMS.map((t, i) => (
            <div
              key={t.key}
              style={{
                display: "flex",
                alignItems: "center",
                gap: 14,
                padding: "14px 0",
                borderBottom: `1px solid ${
                  i === PREF_ITEMS.length - 1 ? "transparent" : "var(--line2)"
                }`,
              }}
            >
              <div style={{ minWidth: 0, flex: 1 }}>
                <div style={{ fontSize: 13.5 }}>{t.label}</div>
                <div
                  style={{ fontSize: 11.5, color: "var(--dim)", marginTop: 5 }}
                >
                  {t.hint}
                </div>
              </div>
              <Toggle
                on={state.prefs[t.key]}
                onClick={() => togglePref(t.key)}
                label={t.label}
              />
            </div>
          ))}
        </div>

        <div
          className="glass"
          style={{
            border: "1px solid var(--line)",
            borderRadius: 20,
            flex: "none",
            boxShadow: "var(--shSm)",
            overflow: "hidden",
          }}
        >
          <div
            style={{
              padding: "16px 18px 12px",
              display: "flex",
              alignItems: "center",
              gap: 12,
              flexWrap: "wrap",
            }}
          >
            <div style={{ fontSize: 14, fontWeight: 600 }}>环境变量</div>
            <span style={{ flex: 1 }} />
            <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
              {S.map((s) => {
                const on = state.envSel === s.id;
                return (
                  <button
                    key={s.id}
                    onClick={() => patch({ envSel: s.id })}
                    style={{
                      padding: "6px 12px",
                      borderRadius: 12,
                      fontSize: 12,
                      cursor: "pointer",
                      fontFamily: "inherit",
                      background: on ? onGlass : "transparent",
                      border: `1px solid ${on ? selBd : "var(--line2)"}`,
                      color: on ? selTx : "var(--mu)",
                    }}
                  >
                    {s.name}
                  </button>
                );
              })}
            </div>
          </div>
          <div
            style={{
              display: "flex",
              gap: 14,
              padding: "10px 18px",
              fontSize: 11,
              color: "var(--dim)",
              letterSpacing: ".08em",
              borderBottom: "1px solid var(--line2)",
            }}
          >
            <div style={{ width: 220, flex: "none" }}>变量名</div>
            <div style={{ flex: 1 }}>值</div>
            <div style={{ width: 62, flex: "none" }} />
          </div>
          {envRows.map((e) => (
            <div
              key={e.k}
              style={{
                display: "flex",
                alignItems: "center",
                gap: 14,
                padding: "11px 18px",
                borderBottom: "1px solid var(--line2)",
                fontFamily: "JetBrains Mono,monospace",
                fontSize: 12,
              }}
            >
              <div
                style={{
                  width: 220,
                  flex: "none",
                  color: "var(--cy)",
                  overflow: "hidden",
                  textOverflow: "ellipsis",
                  whiteSpace: "nowrap",
                }}
              >
                {e.k}
              </div>
              <div
                style={{
                  flex: 1,
                  minWidth: 0,
                  color: "var(--mu)",
                  background: "var(--sunk)",
                  border: "1px solid var(--line2)",
                  borderRadius: 10,
                  padding: "7px 11px",
                  overflow: "hidden",
                  textOverflow: "ellipsis",
                  whiteSpace: "nowrap",
                }}
              >
                {e.v}
              </div>
              <div
                style={{
                  width: 62,
                  flex: "none",
                  display: "flex",
                  justifyContent: "flex-end",
                  gap: 6,
                }}
              >
                <button
                  className="mini-btn to-cy"
                  onClick={() =>
                    cur &&
                    patch({
                      screen: "new",
                      formMode: "edit",
                      form: configToForm(cur),
                    })
                  }
                  title="编辑"
                  aria-label="编辑"
                  style={{
                    width: 26,
                    height: 24,
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    borderRadius: 9,
                    cursor: "pointer",
                    fontFamily: "inherit",
                  }}
                >
                  <Icon d={UI.edit} size={13} />
                </button>
                <button
                  className="mini-btn to-err"
                  onClick={() =>
                    cur &&
                    saveService({
                      ...cur,
                      env: cur.env.filter((x) => x.k !== e.k),
                    })
                  }
                  title="删除"
                  aria-label="删除"
                  style={{
                    width: 26,
                    height: 24,
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    borderRadius: 9,
                    cursor: "pointer",
                    fontFamily: "inherit",
                  }}
                >
                  <Icon d={UI.trash} size={13} />
                </button>
              </div>
            </div>
          ))}
          <div style={{ padding: "12px 18px 16px" }}>
            <button
              className="dashed"
              onClick={() =>
                cur &&
                patch({
                  screen: "new",
                  formMode: "edit",
                  form: {
                    ...configToForm(cur),
                    env: [...cur.env, { k: "", v: "" }],
                  },
                })
              }
              style={{
                display: "flex",
                alignItems: "center",
                gap: 8,
                borderRadius: 12,
                padding: "9px 14px",
                fontSize: 12.5,
                cursor: "pointer",
                fontFamily: "inherit",
              }}
            >
              <Icon d={UI.plus} size={14} sw={1.9} />
              添加变量
            </button>
          </div>
        </div>

        <div
          style={{
            display: "grid",
            gridTemplateColumns: "repeat(auto-fit,minmax(min(280px,100%),1fr))",
            gap: 12,
            flex: "none",
          }}
        >
          <div
            className="glass"
            style={{
              border: "1px solid var(--line)",
              borderRadius: 20,
              padding: "16px 18px",
              boxShadow: "var(--shSm)",
            }}
          >
            <div style={{ fontSize: 14, fontWeight: 600 }}>日志</div>
            <div
              style={{
                display: "flex",
                flexDirection: "column",
                gap: 12,
                marginTop: 14,
              }}
            >
              {logPrefs.map((lp) => (
                <div key={lp.label}>
                  <div
                    style={{
                      display: "flex",
                      alignItems: "baseline",
                      justifyContent: "space-between",
                    }}
                  >
                    <span style={{ fontSize: 12.5, color: "var(--mu)" }}>
                      {lp.label}
                    </span>
                    <span
                      style={{ fontSize: 13, fontWeight: 600, color: "var(--cy)" }}
                    >
                      {lp.value}
                    </span>
                  </div>
                  <div
                    style={{
                      height: 5,
                      borderRadius: 5,
                      background: "var(--sunk)",
                      border: "1px solid var(--line2)",
                      marginTop: 8,
                      overflow: "hidden",
                    }}
                  >
                    <div
                      style={{
                        height: "100%",
                        background: "var(--cy)",
                        width: lp.bar,
                      }}
                    />
                  </div>
                </div>
              ))}
            </div>
          </div>

          <div
            className="glass"
            style={{
              border: "1px solid var(--line)",
              borderRadius: 20,
              padding: "16px 18px",
              boxShadow: "var(--shSm)",
            }}
          >
            <div style={{ fontSize: 14, fontWeight: 600 }}>快捷键</div>
            <div
              style={{
                display: "flex",
                flexDirection: "column",
                gap: 2,
                marginTop: 10,
              }}
            >
              {SHORTCUTS.map((sc) => (
                <div
                  key={sc.label}
                  style={{
                    display: "flex",
                    alignItems: "center",
                    gap: 12,
                    padding: "8px 0",
                  }}
                >
                  <span
                    style={{
                      flex: 1,
                      minWidth: 0,
                      fontSize: 12.5,
                      color: "var(--mu)",
                      overflow: "hidden",
                      textOverflow: "ellipsis",
                      whiteSpace: "nowrap",
                    }}
                  >
                    {sc.label}
                  </span>
                  <span
                    style={{
                      flex: "none",
                      fontFamily: "JetBrains Mono,monospace",
                      fontSize: 11.5,
                      background: "var(--sunk)",
                      border: "1px solid var(--line2)",
                      borderRadius: 9,
                      padding: "4px 9px",
                    }}
                  >
                    {sc.key}
                  </span>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
