import { useEffect, useRef } from "react";
import { LogicalSize, getCurrentWindow } from "@tauri-apps/api/window";
import { inTauri } from "./api";
import { MenuBarBody, panelShell } from "./overlays/MenuBarBody";
import { useMenubar } from "./store";

/**
 * 系统菜单栏图标点开的独立窗口。
 * 内容高度随服务数量变化，渲染后把窗口尺寸调到刚好。
 */
export default function MenubarApp() {
  const { services, cores, toggle, startAll, stopAll, showMain } = useMenubar();
  const box = useRef<HTMLDivElement>(null);

  // 窗口本身是透明的，文档背景必须一并透明，否则页面底色会糊成一块深色矩形。
  // main.tsx 已按 hash 设过 data-mode，这里再兜一次，避免依赖单一入口。
  useEffect(() => {
    const root = document.documentElement;
    root.dataset.mode = "menubar";
    root.style.background = "transparent";
    document.body.style.background = "transparent";
  }, []);

  // 菜单栏面板跟随系统外观，而不是主窗口里手动切换的主题
  useEffect(() => {
    const mq = window.matchMedia("(prefers-color-scheme: dark)");
    const apply = () => {
      document.documentElement.dataset.theme = mq.matches ? "dark" : "light";
    };
    apply();
    mq.addEventListener("change", apply);
    return () => mq.removeEventListener("change", apply);
  }, []);

  useEffect(() => {
    if (!inTauri || !box.current) return;
    const h = Math.ceil(box.current.getBoundingClientRect().height);
    // 调不动窗口尺寸不该连累面板本身
    try {
      void getCurrentWindow().setSize(new LogicalSize(326, h));
    } catch (e) {
      console.error("菜单栏窗口调整尺寸失败", e);
    }
  }, [services.length]);

  return (
    <div
      style={{
        background: "transparent",
        color: "var(--tx)",
        fontFamily:
          "Inter Tight,-apple-system,BlinkMacSystemFont,PingFang SC,sans-serif",
        fontSize: 13.5,
      }}
    >
      <div ref={box} style={panelShell}>
        <MenuBarBody
          services={services}
          cores={cores}
          onToggle={toggle}
          onStartAll={startAll}
          onStopAll={stopAll}
          onOpenMain={showMain}
        />
      </div>
    </div>
  );
}
