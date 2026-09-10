import { invoke } from "@tauri-apps/api/core";
import { open } from "@tauri-apps/plugin-dialog";
import { listen, type UnlistenFn } from "@tauri-apps/api/event";
import type {
  AppConfig,
  LogLine,
  Prefs,
  ServiceConfig,
  Snapshot,
} from "./types";

/**
 * 是否运行在 Tauri 窗口里。用 `pnpm dev` 在普通浏览器打开时为 false，
 * 此时没有后端可调，界面会停在空状态。
 */
export const inTauri =
  typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;

async function call<T>(cmd: string, args?: Record<string, unknown>): Promise<T | null> {
  if (!inTauri) return null;
  try {
    return await invoke<T>(cmd, args);
  } catch (e) {
    console.error(`invoke ${cmd} 失败`, e);
    return null;
  }
}

export const api = {
  getConfig: () => call<AppConfig>("get_config"),
  saveService: (svc: ServiceConfig) => call<void>("save_service", { svc }),
  deleteService: (id: string) => call<void>("delete_service", { id }),
  reorderServices: (ids: string[]) => call<void>("reorder_services", { ids }),
  setPrefs: (prefs: Prefs) => call<void>("set_prefs", { prefs }),

  start: (id: string) => call<void>("start_service", { id }),
  stop: (id: string) => call<void>("stop_service", { id }),
  restart: (id: string) => call<void>("restart_service", { id }),
  startAll: () => call<void>("start_all"),
  stopAll: () => call<void>("stop_all"),

  snapshot: () => call<Snapshot>("snapshot"),
  getLogs: () => call<LogLine[]>("get_logs"),
  clearLogs: () => call<void>("clear_logs"),

  showMain: () => call<void>("show_main"),
  hideMenubar: () => call<void>("hide_menubar"),
};

/**
 * 打开系统目录选择器，返回选中的绝对路径；取消或不在 Tauri 里返回 null。
 * 选中的目录只是写进输入框，不需要文件读写权限，因此只申请了 dialog:allow-open。
 */
export async function pickFolder(defaultPath?: string): Promise<string | null> {
  if (!inTauri) return null;
  try {
    const picked = await open({
      directory: true,
      multiple: false,
      title: "选择工作目录",
      // 相对路径和 ~ 开头的写法系统对话框不认，只有绝对路径才当默认位置
      defaultPath: defaultPath?.startsWith("/") ? defaultPath : undefined,
    });
    return typeof picked === "string" ? picked : null;
  } catch (e) {
    console.error("目录选择器打开失败", e);
    return null;
  }
}

/** 订阅主窗口焦点变化，返回取消订阅函数 */
export async function onMainFocus(
  cb: (focused: boolean) => void,
): Promise<UnlistenFn> {
  if (!inTauri) return () => {};
  return listen<boolean>("main-focus", (e) => cb(e.payload));
}

/** 订阅后端事件，返回取消订阅函数 */
export async function subscribe(handlers: {
  onLogs: (lines: LogLine[]) => void;
  onChanged: () => void;
}): Promise<UnlistenFn> {
  if (!inTauri) return () => {};
  const offs = await Promise.all([
    listen<LogLine[]>("logs", (e) => handlers.onLogs(e.payload)),
    listen("services-changed", () => handlers.onChanged()),
  ]);
  return () => offs.forEach((off) => off());
}
