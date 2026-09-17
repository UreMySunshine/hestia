import SwiftUI

struct Overview: View {
    let onEdit: (ServiceConfig) -> Void
    @Environment(Store.self) private var store
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageTitle(text: "总览", detail: subtitle)

            if store.services.isEmpty {
                ScrollView {
                    EmptyState(onNew: { onEdit(.blank()) })
                        .padding(.horizontal, Chrome.gutter)
                        .padding(.bottom, 28)
                }
                .scrollIndicators(.never)
                .edgeFade()
            } else {
                // 整页不滚动，最近活动与报错两张卡占满剩余高度，各自在卡内滚动。
                // 窗口最矮 680pt 时两张卡仍能放下标题和一两行
                VStack(spacing: 12) {
                    summary
                    StatsRow()
                    Timeline()
                    HStack(spacing: 12) {
                        ActivityCard()
                        ProblemsCard()
                    }
                    .frame(maxHeight: .infinity)
                }
                .padding(.horizontal, Chrome.gutter)
                // 与侧边栏卡片的下沿对齐
                .padding(.bottom, Chrome.inset)
            }
        }
    }

    private var subtitle: String {
        var parts = ["\(store.runningCount) 个运行中", "\(store.stoppedCount) 个已停止"]
        if store.errorCount > 0 { parts.append("\(store.errorCount) 个异常") }
        return parts.joined(separator: " · ")
    }

    // MARK: 顶部汇总

    private var summary: some View {
        // 整张卡共用一块底色，分隔线用独立的矩形填满行高——
        // 设计稿的 flex 行会把子项撑到等高，HStack 不会
        Card(radius: 14) {
            VStack(spacing: 0) {
                FlexRow(items: [(290, true), (0.5, false), (205, true), (0.5, false), (205, true)]) {
                    health
                    vRule
                    miniChart(
                        label: "CPU 总占用",
                        value: String(Int(store.totalCpu.rounded())),
                        unit: "%",
                        foot: "满刻度 \(store.cores) 核",
                        series: store.totalCpuHist,
                        max: Double(store.cores) * 100,
                        color: theme.blue)
                    vRule
                    miniChart(
                        label: "内存",
                        value: String(format: "%.1f", store.totalMem / 1024),
                        unit: "GB",
                        foot: "共 \(Machine.memoryGB) GB 可用",
                        series: store.totalMemHist,
                        max: Machine.memoryMB,
                        color: theme.teal)
                }
                Rectangle().fill(theme.sep).frame(height: 0.5)
                distribution
            }
        }
        .clipShape(.rect(cornerRadius: 14))
    }

    private var vRule: some View {
        Rectangle().fill(theme.sep).frame(width: 0.5)
    }

    private var health: some View {
        let h = healthCopy
        return HStack(spacing: 15) {
            HealthRing(running: store.runningCount, error: store.errorCount, total: store.services.count)
                .frame(width: 76, height: 76)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Dot(state: h.state, size: 8)
                    Text(h.title)
                        .font(.system(size: 15, weight: .semibold))
                        .tracking(-0.18)
                        .foregroundStyle(theme.ink)
                        .lineLimit(1)
                        .lineBox(15)
                }
                Text(h.sub)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 17)
        .frame(minWidth: 290, maxWidth: .infinity, alignment: .leading)
    }

    private var healthCopy: (title: String, sub: String, state: RunState) {
        let n = store.services.count
        if store.errorCount > 0 {
            return (
                "\(store.errorCount) 个服务异常",
                "其余 \(store.runningCount) 个运行正常 · 建议先查看日志",
                .error)
        }
        if store.stoppedCount > 0 {
            return (
                "\(store.runningCount)/\(n) 个服务在运行",
                "\(store.stoppedCount) 个尚未启动 · 其余一切正常",
                .stopped)
        }
        let longest = store.services.map { store.status($0.id).up }.max() ?? 0
        // 时长内部用不换行空格，窄栏里不会把「秒」单独挤到下一行
        let span = Fmt.uptime(longest).replacingOccurrences(of: " ", with: "\u{00A0}")
        return ("全部服务运行正常", "共 \(n) 个服务 · 已持续 \(span)", .running)
    }

    private func miniChart(
        label: String, value: String, unit: String, foot: String,
        series: [Double], max: Double?, color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(theme.ink3)
                .lineBox(11.5)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 25, weight: .semibold).monospacedDigit())
                    .tracking(-0.65)
                    .foregroundStyle(theme.ink)
                    .lineBox(25)
                Text(unit)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.ink3)
                Spacer()
                Text(foot)
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.ink3)
            }
            Spark(values: series, max: max, line: color, fill: color.opacity(0.12))
                .frame(height: 30)
                .padding(.top, 5)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 17)
        .frame(minWidth: 205, maxWidth: .infinity, alignment: .leading)
    }

    private var distribution: some View {
        let groups: [(label: StateFilter, count: Int, color: Color)] = [
            (.running, store.runningCount, theme.green),
            (.stopped, store.stoppedCount, theme.dim),
            (.error, store.errorCount, theme.red),
        ].filter { $0.count > 0 }
        let total = Swift.max(1, store.services.count)

        return HStack(spacing: 16) {
            GeometryReader { geo in
                HStack(spacing: 3) {
                    ForEach(groups, id: \.label) { g in
                        Capsule()
                            .fill(g.color)
                            .frame(width: geo.size.width * CGFloat(g.count) / CGFloat(total))
                    }
                }
            }
            .frame(height: 6)
            .frame(minWidth: 160)

            HStack(spacing: 5) {
                ForEach(groups, id: \.label) { g in
                    HStack(spacing: 6) {
                        Circle().fill(g.color).frame(width: 6, height: 6)
                        Text(g.label.rawValue)
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme.ink2)
                        Text("\(g.count)")
                            .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                            .foregroundStyle(theme.ink)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(theme.fill, in: .rect(cornerRadius: 7))
                }
            }
            .fixedSize()
        }
        .padding(.horizontal, 18)
        .padding(.top, 13)
        .padding(.bottom, 14)
    }
}

// MARK: 健康环

private struct HealthRing: View {
    let running: Int
    let error: Int
    let total: Int
    @Environment(\.theme) private var theme

    /// 设计稿在 120 单位的视窗里画 r=53、描边 7 的圆，显示尺寸 76pt
    private static let stroke: CGFloat = 7 * 76 / 120
    private static let inset: CGFloat = 76 / 2 - 53 * 76 / 120 - stroke / 2

    var body: some View {
        let n = max(1, total)
        // 多于一个服务时段间留缝，只有一个时整圈连续
        let gap = total > 1 ? 0.012 : 0.0
        ZStack {
            Circle()
                .stroke(theme.fill2, lineWidth: Self.stroke)
            arc(from: 0, count: running, of: n, gap: gap, color: theme.green)
            arc(from: running, count: error, of: n, gap: gap, color: theme.red)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(running)")
                    .font(.system(size: 23, weight: .semibold).monospacedDigit())
                    .tracking(-0.69)
                    .foregroundStyle(theme.ink)
                Text("/\(total)")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(theme.ink3)
            }
        }
        .padding(Self.inset + Self.stroke / 2)
    }

    @ViewBuilder
    private func arc(from start: Int, count: Int, of n: Int, gap: Double, color: Color) -> some View {
        if count > 0 {
            Circle()
                .trim(
                    from: Double(start) / Double(n),
                    to: Double(start + count) / Double(n) - gap)
                .stroke(color, style: StrokeStyle(lineWidth: Self.stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.75, dampingFraction: 0.9), value: count)
        }
    }
}

// MARK: 本次运行

private struct CardHeader: View {
    let title: String
    var note = ""
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(theme.ink)
            Spacer()
            Text(note)
                .font(.system(size: 11))
                .foregroundStyle(theme.ink3)
        }
    }
}

/// 启动、异常退出、重启次数与最长的一段连续运行
private struct StatsRow: View {
    @Environment(Store.self) private var store
    @Environment(\.theme) private var theme

    var body: some View {
        // 只读分钟节拍与粗粒度的计数，每拍采样不会让这里重绘
        let now = max(Date(), store.minute)
        let briefs = store.services.map { store.brief($0.id) }
        let errors = briefs.reduce(0) { $0 + $1.errors }
        let longest = store.spans.values.joined()
            .map { ($0.end ?? now).timeIntervalSince($0.start) }
            .max()
        HStack(spacing: 12) {
            tile("启动", "\(store.starts)", unit: "次", icon: UIIcon.play, color: theme.green)
            tile(
                "异常退出", "\(errors)", unit: "次", icon: UIIcon.warn, color: theme.red,
                tint: errors > 0 ? theme.redTx : nil)
            // 核心的重启计数包含手动重启与崩溃后的自动重启
            tile(
                "重启", "\(briefs.reduce(0) { $0 + $1.restarts })", unit: "次",
                icon: UIIcon.restart, color: theme.orange)
            tile("最长连续运行", longest.map(Self.minutes) ?? "—", icon: UIIcon.clock, color: theme.blue)
        }
    }

    private static func minutes(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        return m < 1 ? "不到 1 分钟" : m < 60 ? "\(m) 分钟" : "\(m / 60) 小时 \(m % 60) 分"
    }

    private func tile(
        _ label: String, _ value: String, unit: String = "", icon: String, color: Color,
        tint: Color? = nil
    ) -> some View {
        Card {
            HStack(spacing: 12) {
                Glyph(path: icon, lineWidth: 2)
                    .foregroundStyle(color)
                    .frame(width: 17, height: 17)
                    .frame(width: 34, height: 34)
                    .background(color.opacity(0.13), in: .rect(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.ink3)
                        .lineLimit(1)
                        .lineBox(11.5)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(value)
                            .font(.system(size: 19, weight: .semibold).monospacedDigit())
                            .tracking(-0.4)
                            .foregroundStyle(tint ?? theme.ink)
                            .lineLimit(1)
                        Text(unit)
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme.ink3)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 所有服务合在一条状态条上，每格一段时间，按这段时间里最严重的情况着色
private struct Timeline: View {
    @Environment(Store.self) private var store
    @Environment(\.theme) private var theme

    private static let count = 60
    private static let length: TimeInterval = 120
    private static let gap: CGFloat = 3

    private enum Kind {
        /// Hestia 还没启动，没有数据
        case none
        /// 没有服务在运行
        case idle
        case up
        /// 有服务停在异常状态
        case degraded
        /// 有服务异常退出
        case down
    }

    private struct Slot {
        let start: Date
        let kind: Kind
        let running: Int
        let crashes: Int
    }

    var body: some View {
        // 按分钟重绘；启停与异常记录变化时另会立即重绘
        let now = max(Date(), store.minute)
        // 格子边界对齐整点，最后一格是正在进行的这一段
        let end = Date(
            timeIntervalSince1970: (now.timeIntervalSince1970 / Self.length).rounded(.up) * Self.length)
        let start = end.addingTimeInterval(-Double(Self.count) * Self.length)
        let slots = (0..<Self.count).map { slot(at: start.addingTimeInterval(Double($0) * Self.length), now: now) }
        Card {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("运行时间线")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(theme.ink)
                    Spacer()
                    legend(.up, "运行中")
                    legend(.degraded, "停在异常")
                    legend(.down, "异常退出")
                    legend(.idle, "无服务运行")
                    legend(.none, "Hestia 未运行")
                }
                // 一个 Canvas 画全部格子，每拍刷新时不必逐个布局 60 个视图
                Canvas { ctx, size in
                    let pitch = (size.width + Self.gap) / CGFloat(slots.count)
                    for (i, s) in slots.enumerated() {
                        let r = CGRect(x: CGFloat(i) * pitch, y: 0, width: pitch - Self.gap, height: size.height)
                        ctx.fill(Path(roundedRect: r, cornerRadius: 1.5), with: .color(color(s.kind)))
                    }
                }
                .frame(height: 30)
                .overlay(SlotHover(count: Self.count, gap: Self.gap) { describe(slots[$0]) })
                .padding(.top, 12)
                HStack(spacing: 12) {
                    Text("2 小时前")
                    rule
                    Text(ratio(from: max(start, store.launchedAt), to: now))
                    rule
                    Text("现在")
                }
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(theme.ink3)
                .padding(.top, 8)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 14)
        }
    }

    private func legend(_ k: Kind, _ label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color(k))
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(theme.ink3)
        }
    }

    private var rule: some View {
        Rectangle().fill(theme.sep).frame(height: 0.5).frame(maxWidth: .infinity)
    }

    private func slot(at t: Date, now: Date) -> Slot {
        let t1 = min(t.addingTimeInterval(Self.length), now)
        guard t1 > store.launchedAt, t < now else {
            return Slot(start: t, kind: .none, running: 0, crashes: 0)
        }
        func overlaps(_ list: [RunSpan]?) -> Bool {
            list?.contains { $0.start < t1 && ($0.end ?? now) > t } ?? false
        }
        let running = store.spans.values.filter(overlaps).count
        let crashes = store.crashes.values.joined().filter { $0 >= t && $0 < t1 }.count
        let kind: Kind =
            crashes > 0 ? .down
            : store.faultSpans.values.contains(where: overlaps) ? .degraded
            : running > 0 ? .up : .idle
        return Slot(start: t, kind: kind, running: running, crashes: crashes)
    }

    private func color(_ k: Kind) -> Color {
        switch k {
        case .none: theme.fill
        // 与「已停止」同色，和没有数据的浅底色拉开
        case .idle: theme.dim
        case .up: theme.green
        case .degraded: theme.orange
        case .down: theme.red
        }
    }

    private func describe(_ s: Slot) -> (title: String, detail: String) {
        let range =
            "\(Fmt.hourMinute(s.start)) – \(Fmt.hourMinute(s.start.addingTimeInterval(Self.length)))"
        let text =
            switch s.kind {
            case .none: "Hestia 未运行"
            case .idle: "没有服务在运行"
            case .up: "\(s.running) 个服务在运行"
            case .degraded: "\(s.running) 个服务在运行，有服务停在异常状态"
            case .down: "异常退出 \(s.crashes) 次"
            }
        return (range, text)
    }

    /// 观察期内没有任何服务处于异常状态的时间占比。各服务的异常时段先合并，重叠部分只算一次
    private func ratio(from t0: Date, to t1: Date) -> String {
        let total = t1.timeIntervalSince(t0)
        guard total > 0 else { return "" }
        let clipped = store.faultSpans.values.joined()
            .map { (max($0.start, t0), min($0.end ?? t1, t1)) }
            .filter { $0.0 < $0.1 }
            .sorted { $0.0 < $1.0 }
        var faulty: TimeInterval = 0
        var cursor = t0
        for (a, b) in clipped where b > cursor {
            faulty += b.timeIntervalSince(max(a, cursor))
            cursor = b
        }
        let pct = (1 - faulty / total) * 100
        return "\(pct.formatted(.number.precision(.fractionLength(0...1))))% 时间无异常"
    }
}

// MARK: 最近活动与报错

/// 启动、停止、异常退出与自动重启，最新的在上
private struct ActivityCard: View {
    @Environment(Store.self) private var store
    @Environment(\.theme) private var theme

    var body: some View {
        FeedCard(
            title: "最近活动", note: "本次运行",
            empty: "还没有启停记录", hint: "服务启动、停止或异常退出后会列在这里",
            badge: (UIIcon.bolt, theme.blue),
            items: store.activity.reversed()
        ) { e in
            switch e.lvl {
            case "ERROR": (theme.red, theme.redTx)
            case "WARN": (theme.orange, theme.orangeTx)
            default: (e.text.hasPrefix("已启动") ? theme.green : theme.dim, theme.ink2)
            }
        }
    }
}

/// 服务自身输出里最近的报错与警告，最新的在上
private struct ProblemsCard: View {
    @Environment(Store.self) private var store
    @Environment(\.theme) private var theme

    var body: some View {
        FeedCard(
            title: "最近错误输出", note: "报错与警告",
            empty: "没有报错或警告", hint: "服务输出里的报错与警告会汇总到这里",
            badge: (UIIcon.check, theme.green),
            items: store.problems.reversed(),
            mono: true
        ) { e in
            e.lvl == "ERROR" ? (theme.red, theme.redTx) : (theme.orange, theme.orangeTx)
        }
    }
}

private struct FeedCard: View {
    let title: String
    let note: String
    let empty: String
    let hint: String
    /// 空状态的图标与颜色
    let badge: (path: String, color: Color)
    let items: [LogEntry]
    var mono = false
    /// 圆点颜色与正文颜色
    let colors: (LogEntry) -> (Color, Color)
    @Environment(Store.self) private var store
    @Environment(\.theme) private var theme

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(title: title, note: note)
                    .padding(.horizontal, 15)
                    .padding(.top, 14)
                if items.isEmpty {
                    VStack(spacing: 0) {
                        Glyph(path: badge.path, lineWidth: 2)
                            .foregroundStyle(badge.color)
                            .frame(width: 20, height: 20)
                            .frame(width: 44, height: 44)
                            .background(badge.color.opacity(0.12), in: .circle)
                        Text(empty)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(theme.ink2)
                            .padding(.top, 10)
                        Text(hint)
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme.ink3)
                            .multilineTextAlignment(.center)
                            .padding(.top, 3)
                    }
                    .padding(.horizontal, 15)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(items) { row($0) }
                        }
                        .padding(.horizontal, 7)
                        .padding(.top, 8)
                        .padding(.bottom, 10)
                    }
                    .scrollIndicators(.never)
                    .edgeFade()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func row(_ e: LogEntry) -> some View {
        let (dot, tone) = colors(e)
        return HStack(spacing: 9) {
            Circle().fill(dot).frame(width: 6, height: 6)
            Text(e.name)
                .font(.system(size: 12.5))
                .foregroundStyle(theme.ink)
                .lineLimit(1)
                .fixedSize()
            Text(e.text)
                .font(mono ? .system(size: 11.5, design: .monospaced) : .system(size: 12))
                .foregroundStyle(tone)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(e.text)
            Spacer(minLength: 6)
            Text(Fmt.clock(e.ts))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(theme.ink3)
                .fixedSize()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .contentShape(.rect)
        .hoverHighlight(radius: 7)
        .onTapGesture { if store.service(e.sid) != nil { store.open(e.sid) } }
    }
}

// MARK: 空状态

private struct EmptyState: View {
    let onNew: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Card(radius: 14) {
            VStack(spacing: 12) {
                Glyph(path: UIIcon.bolt, lineWidth: 1.6)
                    .foregroundStyle(theme.blue)
                    .frame(width: 34, height: 34)
                Text("还没有任何服务")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.ink)
                Text("把一条平时手敲的启动命令填进来，之后一键就能拉起")
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.ink2)
                Button(action: onNew) {
                    Text("新建服务")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 7)
                        .background(theme.blue, in: .rect(cornerRadius: 8))
                }
                .buttonStyle(Press(scale: 0.97))
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 46)
        }
    }
}
