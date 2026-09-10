import type { MouseEvent } from "react";
import { IC, UI } from "../data/icons";
import type { Store } from "../store";
import { Icon } from "../components/primitives";

interface CmdItem {
  path: string;
  color: string;
  label: string;
  hint: string;
  run: () => void;
}

export function CommandPalette({ store }: { store: Store }) {
  const { state, patch, toggleSvc, startAll } = store;
  const close = () => patch({ cmdkOpen: false });

  const all: CmdItem[] = [
    ...state.services.map((s) => {
      const run = s.state === "running";
      return {
        path: run ? UI.stop : UI.play,
        color: run ? "var(--err)" : "var(--ac)",
        label: `${run ? "停止 " : "启动 "}${s.name}`,
        hint: s.cmd,
        run: () => {
          toggleSvc(s);
          close();
        },
      };
    }),
    {
      path: UI.grid,
      color: "var(--cy)",
      label: "跳转 · 仪表盘",
      hint: "⌘1",
      run: () => patch({ screen: "overview", cmdkOpen: false }),
    },
    {
      path: IC.pulse,
      color: "var(--cy)",
      label: "跳转 · 监控面板",
      hint: "⌘2",
      run: () => patch({ screen: "monitor", cmdkOpen: false }),
    },
    {
      path: UI.bolt,
      color: "var(--ac)",
      label: "全部启动",
      hint: "⇧⌘R",
      run: () => {
        startAll();
        close();
      },
    },
  ];

  const cq = state.cmdQ.trim().toLowerCase();
  const items = all
    .filter(
      (c) =>
        !cq ||
        c.label.toLowerCase().includes(cq) ||
        c.hint.toLowerCase().includes(cq),
    )
    .slice(0, 8);

  const stop = (e: MouseEvent) => e.stopPropagation();

  return (
    <div
      onClick={close}
      style={{
        position: "fixed",
        inset: 0,
        background: "rgba(4,8,20,.5)",
        backdropFilter: "blur(6px)",
        display: "flex",
        alignItems: "flex-start",
        justifyContent: "center",
        paddingTop: "14vh",
        zIndex: 50,
      }}
    >
      <div
        onClick={stop}
        style={{
          width: 580,
          background: "var(--panelSolid)",
          backdropFilter: "var(--blur)",
          WebkitBackdropFilter: "var(--blur)",
          border: "1px solid var(--line)",
          borderRadius: 22,
          boxShadow:
            "0 30px 80px rgba(0,0,0,.55), inset 0 1px 0 rgba(255,255,255,.25)",
          overflow: "hidden",
          padding: 10,
        }}
      >
        <input
          autoFocus
          value={state.cmdQ}
          onChange={(e) => patch({ cmdQ: e.target.value })}
          placeholder="启动、停止、跳转…"
          style={{
            width: "100%",
            background: "var(--sunk)",
            border: "1px solid var(--line2)",
            outline: "none",
            borderRadius: 16,
            padding: "14px 18px",
            fontSize: 14.5,
            color: "var(--tx)",
            fontFamily: "inherit",
          }}
        />
        <div
          style={{
            maxHeight: 320,
            overflowY: "auto",
            padding: "8px 2px 2px",
            display: "flex",
            flexDirection: "column",
            gap: 3,
          }}
        >
          {items.map((ci) => (
            <button
              key={ci.label}
              className="cmd-item"
              onClick={ci.run}
              style={{
                display: "flex",
                alignItems: "center",
                gap: 12,
                width: "100%",
                borderRadius: 14,
                padding: "10px 13px",
                fontSize: 13,
                cursor: "pointer",
                textAlign: "left",
                fontFamily: "inherit",
                color: "var(--tx)",
              }}
            >
              <span
                style={{
                  width: 18,
                  display: "flex",
                  justifyContent: "center",
                  flex: "none",
                  color: ci.color,
                }}
              >
                <Icon d={ci.path} size={15} />
              </span>
              <span style={{ flex: 1 }}>{ci.label}</span>
              <span
                style={{
                  fontFamily: "JetBrains Mono,monospace",
                  fontSize: 11,
                  color: "var(--dim)",
                  overflow: "hidden",
                  textOverflow: "ellipsis",
                  whiteSpace: "nowrap",
                  maxWidth: 190,
                }}
              >
                {ci.hint}
              </span>
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}
