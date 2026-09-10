import { useEffect } from "react";
import { onMainFocus } from "../api";

/**
 * 背景光晕只在窗口处于前台且可见时运行。
 * 只要有 CSS 动画在跑，WebKit 就持续合成整个窗口，实测空载多耗约 7 个百分点的 CPU，
 * 单纯降帧率压不下去（steps(24) 仍多耗约 4 点）。
 * 焦点状态取自 Rust 侧的窗口事件——WKWebView 里 document.hasFocus() 不反映应用是否在前台。
 */
export function useAmbientMotion() {
  useEffect(() => {
    let focused = true;
    const apply = () => {
      document.documentElement.dataset.anim =
        focused && !document.hidden ? "on" : "off";
    };
    apply();

    const onVisibility = () => apply();
    document.addEventListener("visibilitychange", onVisibility);

    let un: (() => void) | undefined;
    let disposed = false;
    void onMainFocus((f) => {
      focused = f;
      apply();
    }).then((off) => {
      if (disposed) off();
      else un = off;
    });

    return () => {
      disposed = true;
      document.removeEventListener("visibilitychange", onVisibility);
      un?.();
    };
  }, []);
}
