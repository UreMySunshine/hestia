import { useRef, useState } from "react";
import appIcon from "../assets/app-icon.png";
import { IC, UI } from "../data/icons";
import { accents, serviceVM } from "../lib/vm";
import type { Store } from "../store";
import type { Screen } from "../types";
import { Icon } from "./primitives";

const NAV: { k: Screen; path: string; label: string }[] = [
  { k: "overview", path: UI.grid, label: "仪表盘" },
  { k: "monitor", path: IC.pulse, label: "监控面板" },
  { k: "settings", path: UI.cog, label: "设置" },
];

export function Sidebar({ store }: { store: Store }) {
  const { state, patch, openDetail, reorderServices } = store;
  const { onGlass, selBd, selTx } = accents(state.theme);
  const S = state.services;
  const runningCount = S.filter((s) => s.state === "running").length;

  /*
   * 拖拽排序走 pointer 事件而不是 HTML5 的 draggable。
   * WKWebView 里从 <button> 这类表单控件发起原生拖拽并不可靠，实测松手后顺序不变。
   * 移动与松手监听挂在 window 上，指针移出列表范围也不会丢事件。
   */
  const listRef = useRef<HTMLDivElement>(null);
  const moved = useRef(false);
  // 拖动中的服务 id 与插入位置（0..n，表示落在第几项之前）
  const dragRef = useRef<{ id: string; at: number } | null>(null);
  const [drag, setDrag] = useState<{ id: string; at: number } | null>(null);

  /** 指针纵坐标落在哪个插入位置 */
  const slotAt = (y: number) => {
    const items = listRef.current?.querySelectorAll<HTMLElement>("[data-svc]");
    if (!items) return 0;
    for (let i = 0; i < items.length; i++) {
      const r = items[i].getBoundingClientRect();
      if (y < r.top + r.height / 2) return i;
    }
    return items.length;
  };

  const beginDrag = (id: string, y0: number) => {
    moved.current = false;

    const onMove = (e: PointerEvent) => {
      // 4px 之内当作点击，不进入拖动
      if (!moved.current && Math.abs(e.clientY - y0) < 4) return;
      moved.current = true;
      const next = { id, at: slotAt(e.clientY) };
      dragRef.current = next;
      setDrag(next);
    };

    const onUp = () => {
      window.removeEventListener("pointermove", onMove);
      window.removeEventListener("pointerup", onUp);
      window.removeEventListener("pointercancel", onUp);
      const d = dragRef.current;
      if (moved.current && d) {
        const fromIdx = S.findIndex((x) => x.id === d.id);
        if (fromIdx >= 0) {
          const ids = S.map((x) => x.id);
          ids.splice(fromIdx, 1);
          // 移除自身后，插入点在原位置之后的要左移一格
          ids.splice(d.at > fromIdx ? d.at - 1 : d.at, 0, d.id);
          if (ids.some((x, i) => x !== S[i].id)) reorderServices(ids);
        }
      }
      dragRef.current = null;
      setDrag(null);
    };

    window.addEventListener("pointermove", onMove);
    window.addEventListener("pointerup", onUp);
    window.addEventListener("pointercancel", onUp);
  };

  return (
    <div
      className="glass"
      style={{
        width: 228,
        flex: "none",
        border: "1px solid var(--line)",
        borderRadius: 24,
        boxShadow: "var(--sh)",
        display: "flex",
        flexDirection: "column",
        padding: "18px 12px",
        gap: 18,
        overflowY: "auto",
      }}
    >
      <div
        style={{ display: "flex", alignItems: "center", gap: 11, padding: "0 8px" }}
      >
        {/* 用真正的应用图标，和 Dock 里那张一致。图源自带的圆角比这里的 13 小，
            外层用 13 裁一刀只会切掉更多，不会露出白角，所以直接铺满即可 */}
        <img
          src={appIcon}
          alt=""
          style={{
            width: 38,
            height: 38,
            flex: "none",
            borderRadius: 13,
            objectFit: "cover",
            border: "1px solid var(--brandBd)",
          }}
        />
        <div style={{ fontSize: 16, fontWeight: 600, letterSpacing: "-.01em" }}>
          Hestia
        </div>
      </div>

      <div style={{ display: "flex", flexDirection: "column", gap: 3 }}>
        <div
          style={{
            fontSize: 10.5,
            color: "var(--dim)",
            fontWeight: 600,
            letterSpacing: ".14em",
            padding: "0 10px 5px",
          }}
        >
          导航
        </div>
        {NAV.map((n) => {
          const on = state.screen === n.k;
          return (
            <button
              key={n.k}
              onClick={() => patch({ screen: n.k })}
              style={{
                display: "flex",
                alignItems: "center",
                gap: 10,
                border: `1px solid ${on ? selBd : "transparent"}`,
                borderRadius: 14,
                padding: "10px 12px",
                fontSize: 13.5,
                cursor: "pointer",
                textAlign: "left",
                fontFamily: "inherit",
                width: "100%",
                background: on ? onGlass : "transparent",
                color: on ? selTx : "var(--mu)",
                fontWeight: on ? 600 : 400,
                boxShadow: on ? "var(--shSm)" : "none",
              }}
            >
              <span
                style={{ width: 16, height: 16, flex: "none", display: "flex" }}
              >
                <Icon d={n.path} sw={1.7} />
              </span>
              {n.label}
            </button>
          );
        })}
      </div>

      <div
        ref={listRef}
        style={{ display: "flex", flexDirection: "column", gap: 3 }}
      >
        <div
          style={{
            display: "flex",
            justifyContent: "space-between",
            alignItems: "baseline",
            padding: "0 10px 5px",
            fontSize: 10.5,
            fontWeight: 600,
            letterSpacing: ".14em",
            color: "var(--dim)",
          }}
        >
          <span>服务</span>
          <span style={{ color: "var(--ok)" }}>
            {runningCount}
            <span style={{ color: "var(--dim)" }}>/{S.length}</span>
          </span>
        </div>
        {S.map((s, i) => {
          const v = serviceVM(s);
          const on = state.screen === "detail" && state.sel === s.id;
          return (
            <button
              key={s.id}
              data-svc={s.id}
              onClick={() => {
                if (!moved.current) openDetail(s.id);
              }}
              onPointerDown={(e) => {
                if (e.button !== 0) return;
                beginDrag(s.id, e.clientY);
              }}
              style={{
                display: "flex",
                alignItems: "center",
                gap: 9,
                border: `1px solid ${on ? selBd : "transparent"}`,
                borderRadius: 13,
                padding: "8px 12px",
                fontSize: 12.5,
                cursor: drag ? "grabbing" : "pointer",
                textAlign: "left",
                fontFamily: "inherit",
                width: "100%",
                touchAction: "none",
                background: on ? onGlass : "transparent",
                color: on ? selTx : "var(--mu)",
                opacity: drag?.id === s.id ? 0.4 : 1,
                boxShadow: !drag
                  ? "none"
                  : drag.at === i
                    ? "inset 0 2px 0 var(--ac)"
                    : drag.at === i + 1 && i === S.length - 1
                      ? "inset 0 -2px 0 var(--ac)"
                      : "none",
              }}
            >
              <span
                style={{
                  width: 7,
                  height: 7,
                  borderRadius: "50%",
                  flex: "none",
                  background: v.dot,
                  boxShadow: `0 0 8px ${v.dot}`,
                  animation: v.pulse,
                }}
              />
              <span
                style={{
                  flex: 1,
                  overflow: "hidden",
                  textOverflow: "ellipsis",
                  whiteSpace: "nowrap",
                }}
              >
                {s.name}
              </span>
              <span
                style={{
                  fontSize: 10.5,
                  color: "var(--dim)",
                  fontFamily: "JetBrains Mono,monospace",
                }}
              >
                {v.portShort}
              </span>
            </button>
          );
        })}
      </div>
    </div>
  );
}
