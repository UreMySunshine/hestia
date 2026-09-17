import AppKit
import SwiftUI

struct Settings: View {
    @Environment(Store.self) private var store
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageTitle(text: "设置")

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    toggles
                    logs
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
        Card {
            VStack(alignment: .leading, spacing: 0) {
                Text("日志")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.ink)

                meter(
                    label: "日志缓冲",
                    value: "\(Fmt.grouped(store.logs.count)) / \(Fmt.grouped(logCap)) 行",
                    ratio: Double(store.logs.count) / Double(logCap)
                )
                .padding(.top, 12)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func meter(label: String, value: String, ratio: Double) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(label)
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.ink2)
                Spacer()
                Text(value)
                    .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(theme.ink)
            }
            Bar(value: ratio, color: theme.blue)
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
