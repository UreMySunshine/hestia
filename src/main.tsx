import React from "react";
import ReactDOM from "react-dom/client";

import "@fontsource/inter-tight/400.css";
import "@fontsource/inter-tight/500.css";
import "@fontsource/inter-tight/600.css";
import "@fontsource/inter-tight/700.css";
import "@fontsource/jetbrains-mono/400.css";
import "@fontsource/jetbrains-mono/500.css";
import "./styles.css";

import App from "./App";
import MenubarApp from "./MenubarApp";

// 菜单栏窗口加载的是同一份前端，用 hash 区分
const isMenubar = window.location.hash === "#menubar";
if (isMenubar) document.documentElement.dataset.mode = "menubar";

ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(
  <React.StrictMode>{isMenubar ? <MenubarApp /> : <App />}</React.StrictMode>,
);
