import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { api, subscribe } from "./api";
import type {
  AppConfig,
  IconKey,
  LogLine,
  PrefKey,
  Service,
  ServiceConfig,
  ServiceForm,
  Snapshot,
  State,
} from "./types";

/** 采样间隔，与设计稿一致 */
const TICK_MS = 1400;
const HIST = 40;
/** 前端保留的日志行数，后端缓冲更大 */
const LOG_KEEP = 1500;

const zeros = () => Array.from({ length: HIST }, () => 0);

export const EMPTY_FORM: ServiceForm = {
  id: "",
  name: "",
  proj: "",
  kind: "web",
  cwd: "",
  cmd: "",
  stop: "",
  port: "",
  restart: true,
  env: [{ k: "", v: "" }],
};


function initialState(): State {
  return {
    screen: "overview",
    theme: "dark",
    q: "",
    filter: "全部",
    monQ: "",
    monFilter: "全部",
    monSort: "默认",
    sel: "",
    drawerOpen: false,
    view: "grid",
    follow: true,
    logMode: "THIS",
    cmdkOpen: false,
    cmdQ: "",
    envSel: "",
    tourStep: null,
    form: EMPTY_FORM,
    formMode: "new",
    prefs: { autostart: false, autorestart: true, notify: false, quiet: true },
    services: [],
    self: { pid: 0, cpu: 0, mem: 0, up: 0, hist: zeros() },
    logs: [],
    gcpu: zeros(),
    gmem: zeros(),
    cores: 1,
    ready: false,
  };
}

/** 配置变化时重建服务列表，保留已有的状态与采样历史 */
function mergeConfig(prev: Service[], cfg: ServiceConfig[]): Service[] {
  return cfg.map((c) => {
    const old = prev.find((p) => p.id === c.id);
    return {
      ...c,
      state: old?.state ?? "stopped",
      pid: old?.pid ?? 0,
      cpu: old?.cpu ?? 0,
      mem: old?.mem ?? 0,
      up: old?.up ?? 0,
      restarts: old?.restarts ?? 0,
      errors: old?.errors ?? 0,
      portOpen: old?.portOpen ?? false,
      ports: old?.ports ?? [],
      lastError: old?.lastError ?? "",
      hist: old?.hist ?? zeros(),
      mhist: old?.mhist ?? zeros(),
    };
  });
}

function mergeSnapshot(prev: Service[], snap: Snapshot): Service[] {
  return prev.map((p) => {
    const st = snap.services.find((s) => s.id === p.id);
    if (!st) return p;
    return {
      ...p,
      state: st.state,
      pid: st.pid,
      cpu: st.cpu,
      mem: st.mem,
      up: st.up,
      restarts: st.restarts,
      errors: st.errors,
      portOpen: st.portOpen,
      ports: st.ports,
      lastError: st.lastError,
      hist: [...p.hist.slice(1), st.cpu],
      mhist: [...p.mhist.slice(1), st.mem],
    };
  });
}

function formToConfig(f: ServiceForm): ServiceConfig {
  return {
    id: f.id || `s${Date.now().toString(36)}`,
    name: f.name.trim() || "未命名服务",
    proj: f.proj.trim(),
    ic: f.kind,
    cmd: f.cmd.trim(),
    stop: f.stop.trim(),
    cwd: f.cwd.trim(),
    port: Number.parseInt(f.port, 10) || 0,
    autoRestart: f.restart,
    env: f.env.filter((e) => e.k.trim() !== ""),
  };
}

export function configToForm(s: ServiceConfig): ServiceForm {
  return {
    id: s.id,
    name: s.name,
    proj: s.proj,
    kind: s.ic as IconKey,
    cwd: s.cwd,
    cmd: s.cmd,
    stop: s.stop,
    port: s.port ? String(s.port) : "",
    restart: s.autoRestart,
    env: s.env.map((e) => ({ ...e })),
  };
}

export function useHestia() {
  const [state, setState] = useState<State>(initialState);

  const patch = useCallback(
    (p: Partial<State> | ((s: State) => Partial<State>)) => {
      setState((s) => ({ ...s, ...(typeof p === "function" ? p(s) : p) }));
    },
    [],
  );

  const applyConfig = useCallback(
    (cfg: AppConfig) => {
      patch((s) => ({
        services: mergeConfig(s.services, cfg.services),
        prefs: cfg.prefs,
        sel: cfg.services.some((x) => x.id === s.sel)
          ? s.sel
          : (cfg.services[0]?.id ?? ""),
        envSel: cfg.services.some((x) => x.id === s.envSel)
          ? s.envSel
          : (cfg.services[0]?.id ?? ""),
        ready: true,
      }));
    },
    [patch],
  );

  const reloadConfig = useCallback(async () => {
    const cfg = await api.getConfig();
    if (cfg) applyConfig(cfg);
  }, [applyConfig]);

  // 首次载入配置与历史日志
  useEffect(() => {
    let alive = true;
    void (async () => {
      const [cfg, logs] = await Promise.all([api.getConfig(), api.getLogs()]);
      if (!alive) return;
      if (cfg) applyConfig(cfg);
      else patch({ ready: true });
      if (logs) patch({ logs: logs.slice(-LOG_KEEP) });
    })();
    return () => {
      alive = false;
    };
  }, [applyConfig, patch]);

  // 后端事件：日志成批到达，配置或运行状态变化后重新拉取
  useEffect(() => {
    let off: (() => void) | undefined;
    void (async () => {
      off = await subscribe({
        onLogs: (lines: LogLine[]) =>
          patch((s) => ({ logs: [...s.logs, ...lines].slice(-LOG_KEEP) })),
        onChanged: () => void reloadConfig(),
      });
    })();
    return () => off?.();
  }, [patch, reloadConfig]);

  // 资源采样
  useEffect(() => {
    let alive = true;
    const tick = async () => {
      const snap = await api.snapshot();
      if (!alive || !snap) return;
      setState((s) => {
        const services = mergeSnapshot(s.services, snap);
        const totalCpu = services.reduce((a, x) => a + x.cpu, 0);
        const totalMem = services.reduce((a, x) => a + x.mem, 0);
        return {
          ...s,
          services,
          self: {
            ...snap.own,
            hist: [...s.self.hist.slice(1), snap.own.cpu],
          },
          gcpu: [...s.gcpu.slice(1), totalCpu],
          gmem: [...s.gmem.slice(1), totalMem],
          cores: snap.cores || 1,
        };
      });
    };
    void tick();
    const id = setInterval(() => void tick(), TICK_MS);
    return () => {
      alive = false;
      clearInterval(id);
    };
  }, []);

  // ── 操作 ──────────────────────────────────────────────

  const setSvcState = useCallback(
    (id: string, next: "running" | "stopped") =>
      void (next === "running" ? api.start(id) : api.stop(id)),
    [],
  );

  const toggleSvc = useCallback(
    (s: Service) => setSvcState(s.id, s.state === "running" ? "stopped" : "running"),
    [setSvcState],
  );

  const startAll = useCallback(() => void api.startAll(), []);
  const stopAll = useCallback(() => void api.stopAll(), []);
  const restartSvc = useCallback((id: string) => void api.restart(id), []);

  const openDetail = useCallback(
    (id: string) => patch({ screen: "detail", sel: id }),
    [patch],
  );

  const setForm = useCallback(
    (p: Partial<ServiceForm>) => patch((s) => ({ form: { ...s.form, ...p } })),
    [patch],
  );

  /** 侧栏拖拽后按新顺序落盘 */
  const reorderServices = useCallback(
    (ids: string[]) => {
      patch((s) => ({
        services: ids
          .map((id) => s.services.find((x) => x.id === id))
          .filter((x): x is Service => !!x),
      }));
      void api.reorderServices(ids);
    },
    [patch],
  );

  /** 直接写回一条服务配置，后端会广播变更触发重载 */
  const saveService = useCallback(
    (cfg: ServiceConfig) => void api.saveService(cfg),
    [],
  );

  const saveForm = useCallback(async () => {
    const cfg = formToConfig(state.form);
    await api.saveService(cfg);
    await reloadConfig();
    patch({ screen: "overview" });
  }, [state.form, reloadConfig, patch]);

  const deleteForm = useCallback(async () => {
    if (state.form.id) await api.deleteService(state.form.id);
    await reloadConfig();
    patch({ screen: "overview" });
  }, [state.form.id, reloadConfig, patch]);


  const togglePref = useCallback(
    (k: PrefKey) => {
      const next = { ...state.prefs, [k]: !state.prefs[k] };
      patch({ prefs: next });
      void api.setPrefs(next);
    },
    [state.prefs, patch],
  );

  const clearLogs = useCallback(() => {
    void api.clearLogs();
    patch({ logs: [] });
  }, [patch]);

  // ── 快捷键 ────────────────────────────────────────────

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const meta = e.metaKey || e.ctrlKey;
      if (!meta) return;
      const k = e.key.toLowerCase();
      if (k === "k") {
        e.preventDefault();
        patch((s) => ({ cmdkOpen: !s.cmdkOpen, cmdQ: "" }));
      } else if (e.shiftKey && k === "r") {
        e.preventDefault();
        startAll();
      } else if (e.shiftKey && (k === "." || k === ">")) {
        e.preventDefault();
        stopAll();
      } else if (k === "l") {
        e.preventDefault();
        patch((s) => ({ drawerOpen: !s.drawerOpen }));
      } else if (e.shiftKey && k === "t") {
        e.preventDefault();
        patch((s) => ({ theme: s.theme === "light" ? "dark" : "light" }));
      }
    };
    const onEsc = (e: KeyboardEvent) => {
      if (e.key === "Escape") patch({ cmdkOpen: false });
    };
    window.addEventListener("keydown", onKey);
    window.addEventListener("keydown", onEsc);
    return () => {
      window.removeEventListener("keydown", onKey);
      window.removeEventListener("keydown", onEsc);
    };
  }, [patch, startAll, stopAll]);

  const selected = useMemo(
    () => state.services.find((s) => s.id === state.sel) ?? state.services[0],
    [state.services, state.sel],
  );

  return {
    state,
    patch,
    selected,
    setSvcState,
    toggleSvc,
    startAll,
    stopAll,
    restartSvc,
    openDetail,
    setForm,
    saveService,
    reorderServices,
    saveForm,
    deleteForm,
    togglePref,
    clearLogs,
  };
}

export type Store = ReturnType<typeof useHestia>;

/** 菜单栏窗口只需要服务列表与启停，单独用一份轻量状态 */
export function useMenubar() {
  const [services, setServices] = useState<Service[]>([]);
  const [cores, setCores] = useState(1);
  const cfgRef = useRef<ServiceConfig[]>([]);

  const pull = useCallback(async () => {
    const [cfg, snap] = await Promise.all([api.getConfig(), api.snapshot()]);
    if (cfg) cfgRef.current = cfg.services;
    if (!snap) return;
    setCores(snap.cores || 1);
    setServices((prev) => mergeSnapshot(mergeConfig(prev, cfgRef.current), snap));
  }, []);

  useEffect(() => {
    void pull();
    const id = setInterval(() => void pull(), TICK_MS);
    return () => clearInterval(id);
  }, [pull]);

  return {
    services,
    cores,
    toggle: (s: Service) =>
      void (s.state === "running" ? api.stop(s.id) : api.start(s.id)),
    startAll: () => void api.startAll(),
    stopAll: () => void api.stopAll(),
    showMain: () => void api.showMain(),
  };
}
