# Hestia

本地开发服务的启动管理器，macOS 桌面应用。

一个项目跑起来常常要开好几个终端标签：前端、后端、数据库、队列消费者，各占一个窗口，
关机前还得挨个 `Ctrl-C`。Hestia 把这些命令收在一处——一次点击全部拉起，一处看日志，
一处看资源占用，退出时连子进程一起收干净。

![总览](docs/img/dashboard.png)

## 功能

### 总览

服务健康度与 CPU、内存总占用，本次运行以来的启动、异常退出与重启次数。运行时间线把所有服务
合成一条，最近 2 小时每 2 分钟一格，按这段时间里最严重的情况着色，悬停可看该时段的状态。
下方是启停记录与服务输出里的报错、警告，点一条进入对应服务。

### 进程托管

用登录 shell 执行你配置的启动命令，`setsid` 建立独立会话，因此停止时能把整棵进程树
连同孙子进程一起收掉，不会留下占着端口的残留。

- 配了停止命令就先执行它并等 8 秒；没配或没生效则向进程组发 `SIGTERM`，再等 5 秒仍在就 `SIGKILL`
- 非手动退出记为异常；开启自动重启后按 1、2、4、8、16 秒退避重试，最多 5 次
- 工作目录支持 `~`，环境变量逐条注入

### 端口自动推断

不少工具在配置端口被占用时会自动改用别的端口，只看配置值会对不上。Hestia 按进程树的
pid 查实际监听的端口，界面上一律显示探测到的真实值，与配置不一致时在详情页注明配置值。
侧栏里运行中服务的端口可以直接点开，在浏览器里访问对应的 `localhost` 地址。

### 强制退出后的清理

正常退出时向所有被托管的进程组发信号。但那条路覆盖不了 `SIGKILL`，因此另做两层兜底：

- 为 `SIGTERM` / `SIGINT` / `SIGHUP` 装处理函数就地回收
- 运行中的进程组落盘，下次启动先用 `ps` 比对命令行确认还是同一个进程（pid 可能已被复用），再整组回收

### 实时日志

![服务详情与日志](docs/img/detail.png)

`stdout` 与 `stderr` 分别按行读取，按行内容判定级别，内存环形缓冲 4000 行，
每 200ms 成批推给界面，话痨的构建工具也不会刷爆界面。日志在详情页右侧的抽屉里查看（`⌘L` 开关），
可按本服务 / 全部 / 仅错误过滤。

### 监控面板

![监控面板](docs/img/monitor.png)

每 1.4 秒采样一次，按父子关系累加整棵进程树的 CPU 与常驻内存，含 Hestia 自身占用。
支持按状态筛选、按服务名或端口搜索、按 CPU / 内存 / 名称排序。服务与状态两列固定，
窗口较窄时其余列横向滚动。

CPU 用的是「占单核的百分比」，与 `top`、活动监视器同一口径，所以多进程服务超过 100%
是正常的；总览上的 CPU 总占用按本机核数折算满刻度。

### 菜单栏常驻

托盘图标按运行状态切换：有服务在跑时播放尾焰动画，全部停止时是熄火的火箭。
点击图标在正下方展开面板，可以直接启停，也可以一键全部启动 / 全部停止；右键菜单可打开主窗口或退出。
关闭主窗口只是收进菜单栏，进程继续托管。

### 其它

![设置](docs/img/settings.png)

- 侧栏的服务列表支持拖拽排序
- `⌘K` 命令面板，可搜索并启停任意服务
- 深浅两套配色
- 新建服务时可用系统对话框选择工作目录
- 可设置登录后自动常驻菜单栏
- 「设置 — 软件更新」从 GitHub Releases 下载新版，替换当前应用后重启

## 安装

从 [Releases](https://github.com/UreMySunshine/hestia/releases) 下载 DMG，拖进「应用程序」。

应用未做公证签名，首次打开会被 Gatekeeper 拦下。在「系统设置 — 隐私与安全性」里点「仍要打开」即可。

配置保存在 `~/Library/Application Support/com.kira.hestia/config.json`，
首次运行是空的，点总览上的卡片添加第一条启动命令。之后的版本可以在「设置 — 软件更新」里直接安装。

## 从源码运行

需要 Xcode（或 Command Line Tools）与 [Rust](https://rustup.rs)。构建脚本直接调用 `swiftc` 与 `cargo`，不需要 Xcode 工程。

```bash
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)" mac/build.sh --dev
open "mac/build/Hestia Dev.app"
```

`--dev` 换用独立的包标识，可与已安装的正式版同时运行。打通用二进制与 DMG 需要先装 Intel 目标：

```bash
rustup target add x86_64-apple-darwin
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)" mac/build.sh --universal --dmg
```

测试（进程托管的集成测试会真的拉起进程再回收）：

```bash
cargo test --manifest-path core/Cargo.toml
```

旧版的 Tauri 实现保留在 `src/` 与 `src-tauri/`，不再随版本发布。

## 发版

推送到 `main` 时，流水线读取 `core/Cargo.toml` 的版本号；若对应的 `v<版本>` 标签尚不存在，
构建通过后自动打标签并发布 Release，附带通用二进制的 DMG。版本号没变就只构建不发版。

因此发版就是改 `core/Cargo.toml` 的 `version` 后提交推送。应用内的检查更新读取的就是这里的 Release。

## 技术栈

界面是 SwiftUI，进程托管核心是 Rust，编译成动态库经 C 接口供界面调用。

```
core/src/
  manager.rs         进程托管、资源采样、日志缓冲
  lib.rs             供界面调用的 C 接口
  reaper.rs          信号处理，强制退出时就地回收
  shellenv.rs        从登录 shell 取回 PATH
mac/Sources/
  Screens/           总览、服务详情、服务表单、监控、设置、命令面板
  MenuBar/           菜单栏图标与面板
  Core/              界面状态、与核心的桥接、开机自启、软件更新
  Design/            配色、图标与基础组件
mac/build.sh         构建与打包
```

## 已知限制

- 只支持 macOS 14 及以上
