import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct Settings: View {
    @Environment(Store.self) private var store
    @Environment(\.theme) private var theme
    /// 滑块的取值，拖动中也实时生效
    @State private var logLines = Prefs.fallback.logLines
    /// 导入导出的结果，显示在配置卡片底部
    @State private var fileNote: (text: String, failed: Bool)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageTitle(text: "设置")

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    toggles
                    logs
                    configFiles
                    update
                    shortcuts
                }
                .padding(.horizontal, Chrome.gutter)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.never)
            .edgeFade()
        }
    }

    // MARK: 偏好

    private var toggles: some View {
        let items: [(key: WritableKeyPath<Prefs, Bool>, label: String, hint: String)] = [
            (\.autostart, "开机自启 Hestia", "登录后自动在菜单栏常驻"),
            (\.autorestart, "服务崩溃后自动重启", "最多重试 5 次，退避间隔递增"),
            (\.quiet, "隐藏未运行服务的资源曲线", "减少仪表盘上的无效信息"),
        ]
        return Card {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    if i > 0 {
                        Rectangle().fill(theme.sep2).frame(height: 0.5)
                    }
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.label)
                                .font(.system(size: 13))
                                .foregroundStyle(theme.ink)
                                .lineBox(13)
                            Text(item.hint)
                                .font(.system(size: 11.5))
                                .foregroundStyle(theme.ink3)
                                .lineBox(11.5)
                        }
                        Spacer(minLength: 0)
                        Switch(
                            isOn: Binding(
                                get: { store.prefs[keyPath: item.key] },
                                set: { v in
                                    var next = store.prefs
                                    next[keyPath: item.key] = v
                                    store.update(prefs: next)
                                }))
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 11)
                }
            }
        }
    }

    // MARK: 日志与快捷键

    private var logs: some View {
        let range = Prefs.logLinesRange
        return Card {
            VStack(alignment: .leading, spacing: 0) {
                Text("日志")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.ink)
                    .padding(.horizontal, 15)
                    .padding(.top, 14)
                    .padding(.bottom, 4)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 14) {
                        rowText("日志缓冲", hint: "滑钮为上限，蓝色为已缓存的行数，调小时丢掉最早的日志")
                        Spacer(minLength: 0)
                        Text("\(Fmt.grouped(store.logs.count)) / \(Fmt.grouped(logLines)) 行")
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .foregroundStyle(theme.ink)
                    }
                    GaugeSlider(
                        value: $logLines, used: store.logs.count, range: range, step: Prefs.logLinesStep
                    )
                    .help("上限可设 \(Fmt.grouped(range.lowerBound))–\(Fmt.grouped(range.upperBound)) 行")
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 11)

                Rectangle().fill(theme.sep2).frame(height: 0.5)
                    .padding(.horizontal, 15)

                HStack(spacing: 14) {
                    rowText("清除日志", hint: "服务详情里的日志和总览的报错列表一并清空")
                    Spacer(minLength: 0)
                    cardButton("清除", tint: theme.redTx, disabled: store.logs.isEmpty) {
                        store.clearLogs()
                    }
                }
                .padding(.horizontal, 15)
                .padding(.top, 11)
                .padding(.bottom, 13)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear { logLines = store.prefs.logLines }
        // 导入配置等其它途径改了行数时，滑块跟着走
        .onChange(of: store.prefs.logLines) { _, v in logLines = v }
        .onChange(of: logLines) { _, v in
            guard v != store.prefs.logLines else { return }
            var next = store.prefs
            next.logLines = v
            store.update(prefs: next)
        }
    }

    /// 与开关卡片同样的标题加说明
    private func rowText(_ title: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(theme.ink)
                .lineBox(13)
            Text(hint)
                .font(.system(size: 11.5))
                .foregroundStyle(theme.ink3)
                .lineBox(11.5)
                .lineLimit(1)
        }
    }

    private func cardButton(
        _ title: String, tint: Color? = nil, disabled: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint ?? theme.ink)
                .padding(.horizontal, 13)
                .padding(.vertical, 5)
                .background(theme.fill2, in: .rect(cornerRadius: 7))
        }
        .buttonStyle(Press(scale: 0.96))
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }

    // MARK: 配置文件

    private var configFiles: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                Text("配置")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.ink)

                HStack(spacing: 11) {
                    Glyph(path: UIIcon.folder, lineWidth: 2)
                        .foregroundStyle(theme.ink2)
                        .frame(width: 18, height: 18)
                        .frame(width: 34, height: 34)
                        .background(theme.fill, in: .rect(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("导入与导出")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(theme.ink)
                        Text("服务、工作流与偏好设置保存为一个 JSON 文件，可在其它电脑导入")
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme.ink2)
                    }
                    .lineLimit(1)
                }
                .padding(.top, 12)

                HStack(spacing: 8) {
                    Text(fileNote?.text ?? "\(store.services.count) 个服务 · \(store.workflows.count) 个工作流")
                        .font(.system(size: 11.5))
                        .foregroundStyle(fileNote?.failed == true ? theme.redTx : theme.ink3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    cardButton("导入…", action: importFile)
                    cardButton("导出…", action: exportFile)
                }
                .padding(.top, 13)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func exportFile() {
        let panel = NSSavePanel()
        panel.title = "导出配置"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Hestia 配置 \(Date().formatted(.iso8601.year().month().day())).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let error = store.exportConfig(to: url) {
            fileNote = (error, true)
        } else {
            fileNote = ("已导出到 \(Paths.abbreviate(url))", false)
        }
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.title = "导入配置"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let incoming: AppConfig
        switch store.inspectConfig(at: url) {
        case .success(let cfg): incoming = cfg
        case .failure(let e):
            fileNote = (e.message, true)
            return
        }

        let names = Set(incoming.services.map(\.id))
        let dropped = store.services.filter { !names.contains($0.id) }.map(\.name)
        let alert = NSAlert()
        alert.messageText = "导入「\(url.lastPathComponent)」"
        var info = [
            "文件里有 \(incoming.services.count) 个服务、\(incoming.workflows.count) 个工作流。",
            "合并：同一个服务或工作流以文件为准，其余保留，偏好设置不变。",
            "替换：以文件内容为准，偏好设置一并导入，开机自启保留本机设置。",
        ]
        if !dropped.isEmpty {
            info.append("替换会停止并删除：\(dropped.joined(separator: "、"))。")
        }
        alert.informativeText = info.joined(separator: "\n")
        alert.addButton(withTitle: "合并")
        let replace = alert.addButton(withTitle: "替换")
        replace.hasDestructiveAction = !dropped.isEmpty
        alert.addButton(withTitle: "取消")

        let mode: Bool
        switch alert.runModal() {
        case .alertFirstButtonReturn: mode = false
        case .alertSecondButtonReturn: mode = true
        default: return
        }
        if let error = store.importConfig(at: url, replace: mode) {
            fileNote = (error, true)
        } else {
            fileNote = ("已\(mode ? "替换为" : "合并")文件中的 \(incoming.services.count) 个服务、\(incoming.workflows.count) 个工作流", false)
        }
    }

    private var shortcuts: some View {
        let items = [
            ("命令面板", "⌘K"),
            ("全部启动", "⇧⌘R"),
            ("全部停止", "⇧⌘."),
            ("开关日志抽屉", "⌘L"),
            ("切换深浅色", "⌘⇧T"),
        ]
        return Card {
            VStack(alignment: .leading, spacing: 0) {
                Text("快捷键")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.ink)
                VStack(spacing: 0) {
                    ForEach(items, id: \.0) { item in
                        HStack(spacing: 12) {
                            Text(item.0)
                                .font(.system(size: 12.5))
                                .foregroundStyle(theme.ink2)
                                .lineLimit(1)
                            Spacer()
                            Text(item.1)
                                .font(.system(size: 11.5, design: .monospaced))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(theme.fill, in: .rect(cornerRadius: 5))
                        }
                        .padding(.vertical, 6)
                    }
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    // MARK: 软件更新

    private var update: some View {
        let u = Updater.shared
        let v = UpdateFace(u.phase, checkedAt: u.checkedAt, theme: theme)
        return Card {
            VStack(alignment: .leading, spacing: 0) {
                Text("软件更新")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.ink)

                HStack(spacing: 11) {
                    SpinGlyph(path: v.glyph, color: v.iconTx, lineWidth: 2, spinning: v.spins)
                        .frame(width: 18, height: 18)
                        .frame(width: 34, height: 34)
                        .background(v.iconBg, in: .rect(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(v.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(theme.ink)
                        Text(v.sub)
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme.ink2)
                    }
                    .lineLimit(1)
                }
                .padding(.top, 12)

                if let progress = v.progress {
                    Bar(value: progress, color: theme.blue)
                        .padding(.top, 12)
                        .transition(.opacity)
                }

                HStack(spacing: 8) {
                    Text(v.foot)
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.ink3)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Button(action: act) {
                        Text(v.button)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(v.buttonTx)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 5)
                            .background(v.buttonBg, in: .rect(cornerRadius: 7))
                    }
                    .buttonStyle(Press(scale: 0.96))
                    .disabled(v.busy)
                    .opacity(v.busy ? 0.6 : 1)
                }
                .padding(.top, 13)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func act() {
        let u = Updater.shared
        switch u.phase {
        case .idle, .current, .failed: u.check()
        case .found(let r):
            if Updater.installable {
                u.download(r)
            } else {
                NSWorkspace.shared.open(Updater.page)
            }
        case .ready(_, let file): u.install(file)
        case .checking, .downloading, .installing: break
        }
    }
}

/// 更新卡片在各阶段的文案与配色，取自设计稿
@MainActor
private struct UpdateFace {
    var glyph = Glyph.down
    var iconBg: Color
    var iconTx: Color
    var spins = false
    var title: String
    var sub: String
    var foot: String
    var progress: Double?
    var button: String
    var buttonBg: Color
    var buttonTx: Color
    var busy = false

    enum Glyph {
        static let down = "M12 4v10m0 0l-4-4m4 4l4-4M5 19h14"
        static let arc = "M12 4a8 8 0 1 1-8 8"
        static let ok = "M5 12.6l4.2 4.2L19 7.2"
        static let warn = "M12 8v5m0 3.5v.2M12 3l9 17H3z"
    }

    init(_ phase: Updater.Phase, checkedAt: Date?, theme: Theme) {
        let version = Updater.current
        let last = checkedAt.map { "上次检查 " + $0.formatted(date: .omitted, time: .shortened) } ?? "尚未检查"
        let quiet = (bg: theme.fill2, tx: theme.ink)
        let loud = (bg: theme.blue, tx: Color.white)

        switch phase {
        case .idle:
            iconBg = theme.fill; iconTx = theme.ink2
            title = "Hestia \(version)"; sub = "从 GitHub Releases 获取稳定版"; foot = last
            button = "检查更新"; buttonBg = quiet.bg; buttonTx = quiet.tx
        case .checking:
            glyph = Glyph.arc; spins = true
            iconBg = theme.blueSoft; iconTx = theme.blue
            title = "正在检查更新…"; sub = "连接 github.com"; foot = "通常需要几秒"
            button = "检查中"; buttonBg = quiet.bg; buttonTx = theme.ink3; busy = true
        case .current:
            glyph = Glyph.ok
            iconBg = theme.green.opacity(0.14); iconTx = theme.greenTx
            title = "已是最新版本"; sub = "Hestia \(version)"; foot = last
            button = "再次检查"; buttonBg = quiet.bg; buttonTx = quiet.tx
        case .found(let r):
            iconBg = theme.blueSoft; iconTx = theme.blue
            title = "Hestia \(r.version) 可更新"
            // 说明文字可能很长，大小放前面，截断时不被挤掉
            sub = [Self.megabytes(r.size), r.notes].filter { !$0.isEmpty }.joined(separator: " · ")
            foot = "当前 \(version)"
            button = Updater.installable ? "下载并安装" : "前往下载"
            buttonBg = loud.bg; buttonTx = loud.tx
        case .downloading(let r, let pct):
            iconBg = theme.blueSoft; iconTx = theme.blue
            title = "正在下载 \(r.version)"
            sub = "\(Int(pct * 100))% · 共 \(Self.megabytes(r.size))"
            foot = "下载完成后将提示重启"; progress = pct
            button = "下载中"; buttonBg = quiet.bg; buttonTx = theme.ink3; busy = true
        case .ready(let r, _):
            glyph = Glyph.ok
            iconBg = theme.green.opacity(0.14); iconTx = theme.greenTx
            title = "\(r.version) 已准备就绪"
            sub = "重启 Hestia 后生效 · 重启时会停止全部被托管的服务"
            foot = "已下载 \(Self.megabytes(r.size))"
            button = "立即重启"; buttonBg = loud.bg; buttonTx = loud.tx
        case .installing:
            glyph = Glyph.arc; spins = true
            iconBg = theme.blueSoft; iconTx = theme.blue
            title = "正在安装…"; sub = "请勿退出 Hestia"; foot = "即将重新启动"
            button = "安装中"; buttonBg = quiet.bg; buttonTx = theme.ink3; busy = true
        case .failed(let message):
            glyph = Glyph.warn
            iconBg = theme.red.opacity(0.12); iconTx = theme.redTx
            title = "更新没有完成"; sub = message; foot = last
            button = "重试"; buttonBg = quiet.bg; buttonTx = quiet.tx
        }
    }

    private static func megabytes(_ bytes: Int) -> String {
        String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }
}
