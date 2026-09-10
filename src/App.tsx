import { useEffect } from "react";
import { Blobs } from "./components/primitives";
import { Sidebar } from "./components/Sidebar";
import { TitleBar } from "./components/TitleBar";
import { CommandPalette } from "./overlays/CommandPalette";
import { Tour } from "./overlays/Tour";
import { Detail } from "./screens/Detail";
import { Monitor } from "./screens/Monitor";
import { NewService } from "./screens/NewService";
import { Overview } from "./screens/Overview";
import { Settings } from "./screens/Settings";
import { useAmbientMotion } from "./lib/useAmbientMotion";
import { useHestia } from "./store";

export default function App() {
  const store = useHestia();
  const { state } = store;
  useAmbientMotion();

  useEffect(() => {
    document.documentElement.dataset.theme = state.theme;
  }, [state.theme]);

  return (
    <div
      style={{
        height: "100vh",
        position: "relative",
        display: "flex",
        flexDirection: "column",
        background: "var(--page)",
        color: "var(--tx)",
        fontFamily:
          "Inter Tight,-apple-system,BlinkMacSystemFont,PingFang SC,sans-serif",
        fontSize: 13.5,
        overflow: "hidden",
      }}
    >
      <Blobs />
      <TitleBar store={store} />

      <div
        style={{
          position: "relative",
          flex: 1,
          display: "flex",
          minHeight: 0,
          padding: "0 18px 18px",
          gap: 14,
        }}
      >
        <Sidebar store={store} />
        <div style={{ flex: 1, display: "flex", minWidth: 0 }}>
          {state.screen === "overview" && <Overview store={store} />}
          {state.screen === "detail" && <Detail store={store} />}
          {state.screen === "new" && <NewService store={store} />}
          {state.screen === "settings" && <Settings store={store} />}
          {state.screen === "monitor" && <Monitor store={store} />}
        </div>
      </div>

      {state.tourStep !== null && <Tour store={store} />}
      {state.cmdkOpen && <CommandPalette store={store} />}
    </div>
  );
}
