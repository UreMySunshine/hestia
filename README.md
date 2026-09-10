# Hestia

本地开发服务的启动管理器，macOS 桌面应用。

一个项目跑起来常常要开好几个终端标签：前端、后端、数据库、队列消费者，各占一个窗口，
关机前还得挨个 `Ctrl-C`。Hestia 把这些命令收在一处——一次点击全部拉起，一处看日志，
一处看资源占用，退出时连子进程一起收干净。

![仪表盘](docs/img/dashboard.png)

## 功能

### 进程托管

用登录 shell 执行你配置的启动命令，`setsid` 建立独立会话，因此停止时能把整棵进程树
连同孙子进程一起收掉，不会留下占着端口的残留。

- 配了停止命令就先执行它并等 8 秒；没配或没生效则向进程组发 `SIGTERM`，再等 5 秒仍在就 `SIGKILL`
- 非手动退出记为异常；开启自动重启后按 1、2、4、8、16 秒退避重试，最多 5 次
- 工作目录支持 `~`，环境变量逐条注入

### 端口自动推断

不少工具在配置端口被占用时会自动改用别的端口，只看配置值会对不上。Hestia 按进程树的
pid 查实际监听的端口，界面上一律显示探测到的真实值，与配置不一致时标黄提示。

### 强制退出后的清理

正常退出时向所有被托管的进程组发信号。但那条路覆盖不了 `SIGKILL`，因此另做两层兜底：

- 为 `SIGTERM` / `SIGINT` / `SIGHUP` 装处理函数就地回收
- 运行中的进程组落盘，下次启动先用 `ps` 比对命令行确认还是同一个进程（pid 可能已被复用），再整组回收

### 实时日志

![服务详情与日志](docs/img/detail.png)

`stdout` 与 `stderr` 分别按行读取，按行内容判定级别，内存环形缓冲 4000 行，
每 200ms 成批推给界面，话痨的构建工具也不会刷爆界面。可按本服务 / 仅错误 / 全部过滤。

### 监控面板

![监控面板](docs/img/monitor.png)

每 1.4 秒采样一次，按父子关系累加整棵进程树的 CPU 与常驻内存，含 Hestia 自身占用。
支持按状态筛选、按服务名或端口搜索、按 CPU / 内存 / 名称排序。

CPU 用的是「占单核的百分比」，与 `top`、活动监视器同一口径，所以多进程服务超过 100%
是正常的；界面上的颜色阈值与仪表盘的总占用都已按本机核数折算。

### 菜单栏常驻

托盘图标按运行状态切换：有服务在跑时播放尾焰动画，全部停止时是熄火的火箭。
点击图标在正下方展开面板，可以直接启停，也可以一键全部启动 / 全部停止。
关闭主窗口只是收进菜单栏，进程继续托管。

### 其它

![设置](docs/img/settings.png)

- 侧栏的服务列表支持拖拽排序
- `⌘K` 命令面板，可搜索并启停任意服务
- 深浅两套配色
- 新建服务时可用系统对话框选择工作目录

## 安装

从 [Releases](https://github.com/UreMySunshine/hestia/releases) 下载 DMG，拖进「应用程序」。

应用未做公证签名，首次打开会被 Gatekeeper 拦下。在「系统设置 — 隐私与安全性」里点「仍要打开」即可。

配置保存在 `~/Library/Application Support/com.kira.hestia/config.json`，
首次运行是空的，点仪表盘上的卡片添加第一条启动命令。

## 从源码运行

需要 [Node.js](https://nodejs.org)、[pnpm](https://pnpm.io) 和 [Rust](https://rustup.rs)。

```bash
pnpm install
pnpm tauri dev
```

打包：

```bash
pnpm tauri build
```

测试（进程托管的集成测试会真的拉起进程再回收）：

```bash
cargo test --manifest-path src-tauri/Cargo.toml
```

`pnpm dev` 只启前端，没有后端可调，界面会停在空状态，仅适合改样式。

## 发版

推送到 `main` 时，流水线读取版本号；若对应的 `v<版本>` 标签尚不存在，构建通过后自动打标签
并发布 Release，附带通用二进制的 DMG。版本号没变就只构建不发版。

因此发版就是改版本号后提交推送，三处要一起改，不一致会让构建直接失败：

```
package.json            "version"
src-tauri/Cargo.toml    version
src-tauri/tauri.conf.json  "version"
```

## 技术栈

界面是 React + TypeScript，进程托管是 Rust，外壳用 [Tauri](https://tauri.app) v2。

```
src/                 界面
  screens/           仪表盘、服务详情、新建服务、监控面板、设置
  overlays/          菜单栏面板、新手引导、命令面板
  components/        侧栏、顶栏、服务卡片与基础件
  store.ts           界面状态、后端轮询、快捷键
src-tauri/src/
  manager.rs         进程托管核心
  tray.rs            托盘图标与菜单
  dismiss.rs         菜单栏面板的点击别处即收起
  reaper.rs          信号处理，强制退出时就地回收
```

## 已知限制

- 只支持 macOS
- 「开机自启」和「异常时系统通知」两个开关会被保存，但尚未接线
- 菜单栏面板用到 macOS 私有 API 实现透明圆角，自行分发没问题，提交 Mac App Store 会被拒
