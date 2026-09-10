import { UI } from "../data/icons";
import type { Store } from "../store";
import { Icon } from "./primitives";

/**
 * 52px 顶栏。macOS 原生信号灯由窗口自身绘制，titleBarStyle 用 Overlay
 * 让网页内容延伸到标题栏下方，信号灯直接浮在内容上，不会另起一条背景色横条。
 * 这里只为信号灯预留左侧空间，并把整条顶栏设为窗口拖拽区——
 * 拖拽判定看的是鼠标下那个元素自身，所以撑开布局的占位块也要带上该属性。
 */
export function TitleBar({ store }: { store: Store }) {
  const { state, patch } = store;

  return (
    <div
      data-tauri-drag-region
      style={{
        position: "relative",
        height: 52,
        flex: "none",
        display: "flex",
        alignItems: "center",
        gap: 12,
        padding: "0 18px 0 82px",
      }}
    >
      <span data-tauri-drag-region style={{ flex: 1 }} />

      <button
        className="btn-ghost"
        onClick={() => patch({ tourStep: 0 })}
        title="新手引导"
        aria-label="新手引导"
        style={{
          width: 34,
          height: 32,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          backdropFilter: "var(--blur)",
          WebkitBackdropFilter: "var(--blur)",
          borderRadius: 12,
          cursor: "pointer",
          fontFamily: "inherit",
          boxShadow: "var(--shSm)",
        }}
      >
        <Icon d={UI.help} />
      </button>

      <button
        className="btn-ghost btn-cmdk"
        onClick={() => patch({ cmdkOpen: true, cmdQ: "" })}
        style={{
          backdropFilter: "var(--blur)",
          WebkitBackdropFilter: "var(--blur)",
          borderRadius: 12,
          padding: "7px 13px",
          fontSize: 12,
          fontWeight: 500,
          cursor: "pointer",
          fontFamily: "inherit",
          boxShadow: "var(--shSm)",
        }}
      >
        ⌘K 命令面板
      </button>

      <button
        className="btn-ghost"
        onClick={() =>
          patch((s) => ({ theme: s.theme === "light" ? "dark" : "light" }))
        }
        aria-label="切换深浅色"
        style={{
          width: 34,
          height: 32,
          backdropFilter: "var(--blur)",
          WebkitBackdropFilter: "var(--blur)",
          borderRadius: 12,
          cursor: "pointer",
          fontSize: 13,
          fontFamily: "inherit",
          boxShadow: "var(--shSm)",
        }}
      >
        {state.theme === "light" ? "☾" : "☀"}
      </button>
    </div>
  );
}
