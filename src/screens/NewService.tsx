import { pickFolder } from "../api";
import { IC, UI } from "../data/icons";
import { accents } from "../lib/vm";
import type { Store } from "../store";
import type { IconKey } from "../types";
import { Icon, Toggle } from "../components/primitives";

const KINDS: { k: IconKey; label: string }[] = [
  { k: "web", label: "Web / 前端" },
  { k: "api", label: "API 服务" },
  { k: "db", label: "数据库" },
  { k: "queue", label: "Worker" },
  { k: "chip", label: "构建任务" },
];

const cardStyle = {
  border: "1px solid var(--line)",
  borderRadius: 20,
  padding: 18,
  flex: "none",
  boxShadow: "var(--shSm)",
  display: "flex",
  flexDirection: "column",
} as const;

const monoInput = {
  background: "var(--sunk)",
  borderRadius: 12,
  padding: "10px 13px",
  fontSize: 12.5,
  color: "var(--tx)",
  fontFamily: "JetBrains Mono,monospace",
  outline: "none",
} as const;

export function NewService({ store }: { store: Store }) {
  const { state, patch, setForm, saveForm, deleteForm } = store;
  const { onGlass, selBd, selTx } = accents(state.theme);
  const f = state.form;

  const checks = [
    {
      label: f.cmd ? "启动命令已填写" : "请填写启动命令",
      ok: !!f.cmd,
      color: f.cmd ? "var(--ok)" : "var(--warn)",
    },
    {
      label: f.stop ? "停止命令已填写" : "未填停止命令，将发送 SIGTERM",
      ok: !!f.stop,
      color: f.stop ? "var(--ok)" : "var(--warn)",
    },
    {
      label: f.port ? `端口 ${f.port} 用于就绪检查` : "未配置端口，跳过就绪检查",
      ok: !!f.port,
      color: f.port ? "var(--ok)" : "var(--dim)",
    },
    {
      label: f.cwd ? "工作目录已填写" : "未填工作目录，默认继承 Hestia 的目录",
      ok: !!f.cwd,
      color: f.cwd ? "var(--ok)" : "var(--dim)",
    },
  ];

  const back = () => patch({ screen: "overview" });

  // 系统目录选择器给的是绝对路径，直接写回输入框；用户仍可手改成 ~ 开头的写法
  const pickCwd = async () => {
    const dir = await pickFolder(f.cwd);
    if (dir) setForm({ cwd: dir });
  };

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
          onClick={back}
          title="返回"
          aria-label="返回"
          style={{
            width: 34,
            height: 32,
            flex: "none",
            border: "1px solid var(--line)",
            borderRadius: 12,
            background: "var(--glass)",
            color: "var(--mu)",
            cursor: "pointer",
            fontFamily: "inherit",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
          }}
        >
          <Icon d={UI.back} size={15} sw={1.9} />
        </button>
        <div style={{ minWidth: 0 }}>
          <div style={{ fontSize: 25, fontWeight: 600, letterSpacing: "-.02em" }}>
            {state.formMode === "edit" ? "编辑启动配置" : "新建启动配置"}
          </div>
          <div
            style={{
              fontSize: 12.5,
              color: "var(--mu)",
              marginTop: 5,
              overflow: "hidden",
              textOverflow: "ellipsis",
              whiteSpace: "nowrap",
            }}
          >
            保存后可在仪表盘一键启动，也能从菜单栏面板启停
          </div>
        </div>
        <span style={{ flex: 1 }} />
        {state.formMode === "edit" && (
          <button
            className="btn-ghost to-err"
            onClick={() => void deleteForm()}
            style={{
              borderRadius: 13,
              padding: "9px 15px",
              fontSize: 12.5,
              cursor: "pointer",
              fontFamily: "inherit",
            }}
          >
            删除
          </button>
        )}
        <button
          onClick={back}
          style={{
            border: "1px solid var(--line)",
            borderRadius: 13,
            background: "var(--glass)",
            color: "var(--mu)",
            padding: "9px 15px",
            fontSize: 12.5,
            cursor: "pointer",
            fontFamily: "inherit",
          }}
        >
          取消
        </button>
        <button
          onClick={() => void saveForm()}
          style={{
            display: "flex",
            alignItems: "center",
            gap: 8,
            border: "1px solid rgba(255,138,91,.55)",
            borderRadius: 14,
            background:
              "linear-gradient(150deg,rgba(255,138,91,.5),rgba(255,138,91,.16))",
            color: "var(--onAc)",
            padding: "9px 17px",
            fontSize: 12.5,
            fontWeight: 500,
            cursor: "pointer",
            fontFamily: "inherit",
            boxShadow: "var(--shSm)",
          }}
        >
          保存配置
        </button>
      </div>

      <div style={{ flex: 1, minHeight: 0, display: "flex", gap: 14 }}>
        <div
          style={{
            flex: 1,
            minWidth: 0,
            overflowY: "auto",
            overflowX: "hidden",
            padding: "2px 6px 20px",
            display: "flex",
            flexDirection: "column",
            gap: 12,
            scrollbarGutter: "stable",
          }}
        >
          <div className="glass" style={{ ...cardStyle, gap: 14 }}>
            <div style={{ fontSize: 14, fontWeight: 600 }}>基本信息</div>
            <div
              style={{
                display: "grid",
                gridTemplateColumns: "repeat(auto-fit,minmax(min(220px,100%),1fr))",
                gap: 12,
              }}
            >
              {[
                {
                  label: "服务名称",
                  value: f.name,
                  ph: "例如 Web 前端",
                  set: (v: string) => setForm({ name: v }),
                },
                {
                  label: "所属项目",
                  value: f.proj,
                  ph: "例如 shop-frontend",
                  set: (v: string) => setForm({ proj: v }),
                },
              ].map((x) => (
                <label
                  key={x.label}
                  style={{ display: "flex", flexDirection: "column", gap: 7 }}
                >
                  <span style={{ fontSize: 11.5, color: "var(--dim)" }}>
                    {x.label}
                  </span>
                  <input
                    value={x.value}
                    onChange={(e) => x.set(e.target.value)}
                    placeholder={x.ph}
                    style={{
                      background: "var(--sunk)",
                      border: "1px solid var(--line2)",
                      borderRadius: 12,
                      padding: "10px 13px",
                      fontSize: 13,
                      color: "var(--tx)",
                      fontFamily: "inherit",
                      outline: "none",
                    }}
                  />
                </label>
              ))}
            </div>
            <div style={{ display: "flex", flexDirection: "column", gap: 7 }}>
              <span style={{ fontSize: 11.5, color: "var(--dim)" }}>服务类型</span>
              <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
                {KINDS.map((k) => {
                  const on = f.kind === k.k;
                  return (
                    <button
                      key={k.k}
                      onClick={() => setForm({ kind: k.k })}
                      style={{
                        display: "flex",
                        alignItems: "center",
                        gap: 8,
                        padding: "8px 13px",
                        borderRadius: 13,
                        fontSize: 12.5,
                        cursor: "pointer",
                        fontFamily: "inherit",
                        background: on ? onGlass : "var(--sunk)",
                        border: `1px solid ${on ? selBd : "var(--line2)"}`,
                        color: on ? selTx : "var(--mu)",
                      }}
                    >
                      <Icon d={IC[k.k]} size={15} sw={1.7} />
                      {k.label}
                    </button>
                  );
                })}
              </div>
            </div>
          </div>

          <div className="glass" style={{ ...cardStyle, gap: 14 }}>
            <div style={{ fontSize: 14, fontWeight: 600 }}>命令</div>
            {[
              {
                label: "工作目录",
                color: "var(--dim)",
                border: "var(--line2)",
                value: f.cwd,
                ph: "~/dev/my-project",
                set: (v: string) => setForm({ cwd: v }),
                browse: true,
              },
              {
                label: "启动命令",
                color: "var(--ac)",
                border: "rgba(255,138,91,.4)",
                value: f.cmd,
                ph: "pnpm dev --port 5173",
                set: (v: string) => setForm({ cmd: v }),
                browse: false,
              },
              {
                label: "停止命令",
                color: "var(--err)",
                border: "rgba(255,111,145,.35)",
                value: f.stop,
                ph: "kill $(lsof -t -i:5173)",
                set: (v: string) => setForm({ stop: v }),
                browse: false,
              },
            ].map((x) => (
              <label
                key={x.label}
                style={{ display: "flex", flexDirection: "column", gap: 7 }}
              >
                <span style={{ fontSize: 11.5, color: x.color }}>{x.label}</span>
                <div style={{ display: "flex", gap: 8, minWidth: 0 }}>
                  <input
                    value={x.value}
                    onChange={(e) => x.set(e.target.value)}
                    placeholder={x.ph}
                    style={{
                      ...monoInput,
                      flex: 1,
                      minWidth: 0,
                      border: `1px solid ${x.border}`,
                    }}
                  />
                  {x.browse && (
                    <button
                      className="btn-ghost to-cy"
                      onClick={pickCwd}
                      style={{
                        flex: "none",
                        display: "flex",
                        alignItems: "center",
                        gap: 7,
                        borderRadius: 12,
                        padding: "0 14px",
                        fontSize: 12.5,
                        cursor: "pointer",
                        fontFamily: "inherit",
                      }}
                    >
                      <Icon d={UI.folder} size={14} sw={1.7} />
                      选择
                    </button>
                  )}
                </div>
              </label>
            ))}
            <div
              style={{
                display: "grid",
                gridTemplateColumns: "repeat(auto-fit,minmax(min(200px,100%),1fr))",
                gap: 12,
              }}
            >
              <label style={{ display: "flex", flexDirection: "column", gap: 7 }}>
                <span style={{ fontSize: 11.5, color: "var(--dim)" }}>
                  监听端口（可选）
                </span>
                <input
                  value={f.port}
                  onChange={(e) => setForm({ port: e.target.value })}
                  placeholder="5173"
                  style={{ ...monoInput, border: "1px solid var(--line2)" }}
                />
              </label>
              <div
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: 14,
                  background: "var(--sunk)",
                  border: "1px solid var(--line2)",
                  borderRadius: 12,
                  padding: "10px 13px",
                }}
              >
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontSize: 12.5 }}>崩溃后自动重启</div>
                  <div style={{ fontSize: 11, color: "var(--dim)", marginTop: 4 }}>
                    最多重试 5 次
                  </div>
                </div>
                <Toggle
                  on={f.restart}
                  onClick={() => setForm({ restart: !f.restart })}
                  label="崩溃后自动重启"
                />
              </div>
            </div>
          </div>

          <div className="glass" style={{ ...cardStyle, gap: 12 }}>
            <div style={{ fontSize: 14, fontWeight: 600 }}>环境变量</div>
            {f.env.map((e, i) => (
              <div
                key={i}
                style={{ display: "flex", gap: 10, alignItems: "center" }}
              >
                <input
                  value={e.k}
                  onChange={(ev) =>
                    setForm({
                      env: f.env.map((x, j) =>
                        j === i ? { ...x, k: ev.target.value } : x,
                      ),
                    })
                  }
                  placeholder="KEY"
                  style={{
                    width: 220,
                    flex: "none",
                    background: "var(--sunk)",
                    border: "1px solid var(--line2)",
                    borderRadius: 11,
                    padding: "9px 12px",
                    fontSize: 12,
                    color: "var(--cy)",
                    fontFamily: "JetBrains Mono,monospace",
                    outline: "none",
                  }}
                />
                <input
                  value={e.v}
                  onChange={(ev) =>
                    setForm({
                      env: f.env.map((x, j) =>
                        j === i ? { ...x, v: ev.target.value } : x,
                      ),
                    })
                  }
                  placeholder="value"
                  style={{
                    flex: 1,
                    minWidth: 0,
                    background: "var(--sunk)",
                    border: "1px solid var(--line2)",
                    borderRadius: 11,
                    padding: "9px 12px",
                    fontSize: 12,
                    color: "var(--mu)",
                    fontFamily: "JetBrains Mono,monospace",
                    outline: "none",
                  }}
                />
                <button
                  className="mini-btn to-err"
                  onClick={() => setForm({ env: f.env.filter((_, j) => j !== i) })}
                  title="删除"
                  aria-label="删除"
                  style={{
                    width: 28,
                    height: 26,
                    flex: "none",
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
            ))}
            <button
              className="dashed"
              onClick={() => setForm({ env: [...f.env, { k: "", v: "" }] })}
              style={{
                alignSelf: "flex-start",
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
            width: 312,
            flex: "none",
            display: "flex",
            flexDirection: "column",
            gap: 12,
            padding: "2px 2px 20px",
            overflowY: "auto",
          }}
        >
          <div
            style={{
              fontSize: 11.5,
              color: "var(--dim)",
              letterSpacing: ".1em",
              padding: "0 4px",
            }}
          >
            预览
          </div>
          <div
            className="glass"
            style={{
              border: "1px solid var(--line2)",
              borderRadius: 22,
              padding: "17px 18px 15px",
              display: "flex",
              flexDirection: "column",
              gap: 14,
              boxShadow: "var(--sh)",
            }}
          >
            <div style={{ display: "flex", alignItems: "flex-start", gap: 12 }}>
              <div
                style={{
                  width: 42,
                  height: 42,
                  flex: "none",
                  borderRadius: 14,
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  background: "var(--sunk)",
                  border: "1px solid var(--line2)",
                  color: "var(--dim)",
                }}
              >
                <Icon d={IC[f.kind] || IC.chip} size={21} sw={1.7} />
              </div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div
                  style={{
                    fontSize: 15.5,
                    fontWeight: 600,
                    overflow: "hidden",
                    textOverflow: "ellipsis",
                    whiteSpace: "nowrap",
                  }}
                >
                  {f.name || "未命名服务"}
                </div>
                <div
                  style={{
                    fontSize: 11.5,
                    color: "var(--dim)",
                    marginTop: 4,
                    overflow: "hidden",
                    textOverflow: "ellipsis",
                    whiteSpace: "nowrap",
                  }}
                >
                  {f.proj || "未指定项目"}
                </div>
              </div>
              <div
                style={{
                  flex: "none",
                  display: "flex",
                  alignItems: "center",
                  gap: 6,
                  padding: "4px 10px",
                  borderRadius: 11,
                  fontSize: 10.5,
                  background: "var(--sunk)",
                  border: "1px solid var(--line2)",
                  color: "var(--dim)",
                }}
              >
                <span
                  style={{
                    width: 5,
                    height: 5,
                    borderRadius: "50%",
                    background: "var(--dim)",
                  }}
                />
                未启动
              </div>
            </div>
            <div
              style={{
                fontFamily: "JetBrains Mono,monospace",
                fontSize: 11.5,
                color: "var(--mu)",
                background: "var(--sunk)",
                border: "1px solid var(--line2)",
                borderRadius: 13,
                padding: "10px 13px",
                overflow: "hidden",
                textOverflow: "ellipsis",
                whiteSpace: "nowrap",
              }}
            >
              {f.cmd || "尚未填写启动命令"}
            </div>
            <div
              style={{
                display: "flex",
                alignItems: "center",
                gap: 12,
                borderTop: "1px solid var(--line2)",
                paddingTop: 12,
                fontSize: 11.5,
                color: "var(--dim)",
              }}
            >
              <span>{f.port ? `端口 ${f.port}` : "无端口"}</span>
              <span>{f.restart ? "自动重启已开" : "不自动重启"}</span>
            </div>
          </div>

          <div
            className="glass2"
            style={{
              border: "1px solid var(--line2)",
              borderRadius: 18,
              padding: "15px 16px",
              display: "flex",
              flexDirection: "column",
              gap: 10,
            }}
          >
            <div style={{ fontSize: 12.5, fontWeight: 600 }}>检查项</div>
            {checks.map((ck) => (
              <div
                key={ck.label}
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: 10,
                  fontSize: 12,
                  color: "var(--mu)",
                }}
              >
                <span
                  style={{
                    width: 16,
                    height: 16,
                    flex: "none",
                    display: "flex",
                    color: ck.color,
                  }}
                >
                  <Icon d={ck.ok ? UI.check : UI.warn} size={16} sw={2} />
                </span>
                <span
                  style={{
                    minWidth: 0,
                    overflow: "hidden",
                    textOverflow: "ellipsis",
                    whiteSpace: "nowrap",
                  }}
                >
                  {ck.label}
                </span>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
