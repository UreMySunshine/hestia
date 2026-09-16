import SwiftUI

struct Detail: View {
    let onEdit: (ServiceConfig) -> Void
    @Environment(Store.self) private var store
    @Environment(\.theme) private var theme

    /// 抽屉当前的水平位移：0 为完全展开，drawerWidth 为完全收起
    @State private var offset: CGFloat = drawerWidth
    @State private var dragBase: CGFloat?

    private static let width: CGFloat = 392
    private static var drawerWidth: CGFloat { 392 }

    var body: some View {
        if let svc = store.selected {
            VStack(alignment: .leading, spacing: 0) {
                header(svc)
                    .padding(.horizontal, Chrome.gutter)
                // 抽屉从头部下方开始，头部的按钮在抽屉展开时仍可点击
                ZStack(alignment: .topTrailing) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            stats(svc)
                            charts(svc)
                            commands(svc)
                            environment(svc)
                        }
                        .padding(.horizontal, Chrome.gutter)
                        .padding(.bottom, 28)
                    }
                    LogDrawer(
                        service: svc,
                        isOpen: Binding(get: { store.drawerOpen }, set: { store.drawerOpen = $0 }))
                        .frame(width: Self.width)
                        .offset(x: offset)
                        .gesture(dragGesture)
                }
                // 抽屉收起时藏在右侧之外；上方放宽，阴影不在顶边截断
                .mask { Rectangle().padding(.top, -40) }
            }
            // 抽屉开合是全局状态，在别的页面按 ⌘L 后进来要保持一致
            .onAppear { offset = store.drawerOpen ? 0 : Self.width }
            .onChange(of: store.drawerOpen) { _, open in
                withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                    offset = open ? 0 : Self.width
                }
            }
        } else {
            Color.clear
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { g in
                let base = dragBase ?? offset
                dragBase = base
                offset = min(Self.width, max(0, base + g.translation.width))
            }
            .onEnded { g in
                dragBase = nil
                // 按投影位置决定停在哪一端，快速甩动也能贯彻方向
                let projected = offset + g.predictedEndTranslation.width - g.translation.width
                store.drawerOpen = projected < Self.width / 2
                withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                    offset = store.drawerOpen ? 0 : Self.width
                }
            }
    }

    // MARK: 头部

    private func header(_ svc: ServiceConfig) -> some View {
        let st = store.status(svc.id)
        let phase = store.phase(svc.id)
        return HStack(spacing: 13) {
            ChromeButton(path: UIIcon.back, help: "返回", tint: theme.blue) {
                store.screen = .overview
            }

            IconBadge(ic: svc.ic, side: 42, glyph: 23, phase: phase)

            VStack(alignment: .leading, spacing: 2) {
                Text(svc.name)
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(theme.ink)
                    .lineLimit(1)
                    .lineBox(22)
                HStack(spacing: 7) {
                    Dot(phase: phase)
                    Text(phase.label)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(theme.text(phase))
                    Text(metaLine(svc, st))
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme.ink2)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Button { store.toggle(svc.id) } label: {
                    HStack(spacing: 6) {
                        SpinGlyph(
                            path: phase.runIcon, color: phase.quiet ? theme.ink : .white,
                            lineWidth: 2, spinning: phase.busy
                        )
                        .frame(width: 14, height: 14)
                        Text(phase.runLabel)
                            .font(.system(size: 12.5, weight: .medium))
                    }
                    .foregroundStyle(phase.quiet ? theme.ink : .white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        phase.quiet ? theme.fill2 : theme.blue,
                        in: .rect(cornerRadius: 8))
                }
                .buttonStyle(Press(scale: 0.97))

                ChromeButton(path: UIIcon.restart, help: "重启") { store.restart(svc.id) }
                ChromeButton(path: UIIcon.edit, help: "编辑配置") { onEdit(svc) }

                Button {
                    store.drawerOpen.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Glyph(path: UIIcon.panel, lineWidth: 1.8)
                            .frame(width: 15, height: 15)
                        Text("日志").font(.system(size: 12.5))
                    }
                    .foregroundStyle(store.drawerOpen ? theme.blueTx : theme.ink2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(store.drawerOpen ? theme.blueSoft : theme.fill, in: .rect(cornerRadius: 8))
                }
                .buttonStyle(Press(scale: 0.97))
            }
        }
        .padding(.top, Chrome.headerTop)
        .padding(.bottom, 12)
        .padding(.horizontal, 2)
    }

    private func metaLine(_ svc: ServiceConfig, _ st: ServiceStatus) -> String {
        var parts = [st.state == .running ? "PID \(st.pid)" : "未运行"]
        if !svc.proj.isEmpty { parts.append(svc.proj) }
        parts.append("重启 \(st.restarts) 次")
        return parts.joined(separator: " · ")
    }

    // MARK: 指标

    private func stats(_ svc: ServiceConfig) -> some View {
        let st = store.status(svc.id)
        let phase = store.phase(svc.id)
        let items: [(String, String, String, Color)] = [
            (
                "状态", phase.label,
                st.state == .running ? "PID \(st.pid)" : "进程未运行",
                theme.text(phase)
            ),
            ("运行时长", Fmt.uptime(st.up), "重启 \(st.restarts) 次", theme.ink),
            ("端口", portValue(svc, st), portHint(svc, st), theme.ink),
            (
                "错误", String(st.errors),
                st.lastError.isEmpty ? "无异常退出" : st.lastError,
                st.errors > 0 ? theme.redTx : theme.ink
            ),
        ]
        return Card {
            HStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    if i > 0 {
                        Rectangle().fill(theme.sep).frame(width: 0.5)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.0)
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme.ink3)
                        Text(item.1)
                            .font(.system(size: 18, weight: .semibold).monospacedDigit())
                            .tracking(-0.25)
                            .foregroundStyle(item.3)
                            .lineLimit(1)
                            .lineBox(18)
                        Text(item.2)
                            .font(.system(size: 11))
                            .foregroundStyle(theme.ink3)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .frame(minWidth: 130, maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func portValue(_ svc: ServiceConfig, _ st: ServiceStatus) -> String {
        if let p = st.ports.first { return String(p) }
        return svc.port == 0 ? "—" : String(svc.port)
    }

    /// 实测端口与配置端口不一致时说清楚，这是端口被占用后工具自行改用别的端口的常见情形
    private func portHint(_ svc: ServiceConfig, _ st: ServiceStatus) -> String {
        guard st.state == .running else {
            return svc.port == 0 ? "无监听端口" : "未监听"
        }
        if st.ports.isEmpty { return "未探测到监听端口" }
        if svc.port == 0 { return "实际监听" }
        return st.portOpen ? "与配置一致" : "配置为 \(svc.port)"
    }

    // MARK: 曲线

    private func charts(_ svc: ServiceConfig) -> some View {
        let st = store.status(svc.id)
        return HStack(spacing: 12) {
            chart(
                title: "CPU", value: Fmt.cpu(st.cpu), unit: "%",
                series: store.cpuSeries(svc.id), floor: 25, color: theme.blue)
            chart(
                title: "内存", value: String(Int(st.mem.rounded())), unit: "MB",
                series: store.memSeries(svc.id), floor: 64, color: theme.teal)
        }
        .padding(.top, 12)
    }

    private func chart(
        title: String, value: String, unit: String, series: [Double], floor: Double, color: Color
    ) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.ink3)
                    Spacer()
                    Text(value)
                        .font(.system(size: 15, weight: .semibold).monospacedDigit())
                        .tracking(-0.15)
                        .foregroundStyle(theme.ink)
                        .lineBox(15)
                    Text(unit)
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.ink3)
                }
                Spark(
                    values: series, max: nil, floor: floor,
                    line: color, fill: color.opacity(0.11), lineWidth: 1.8)
                    .frame(height: 68)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 13)
        }
    }

    // MARK: 命令与环境

    private func commands(_ svc: ServiceConfig) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "命令")
                .padding(.top, 22)
                .padding(.bottom, 7)
                .padding(.horizontal, 4)
            Card {
                VStack(spacing: 0) {
                    kv("目录", svc.cwd.isEmpty ? "~" : svc.cwd, first: true)
                    kv("启动", svc.cmd, first: false)
                    kv("停止", svc.stop.isEmpty ? "未配置，直接向进程组发信号" : svc.stop, first: false)
                }
            }
        }
    }

    private func kv(_ key: String, _ value: String, first: Bool) -> some View {
        VStack(spacing: 0) {
            if !first {
                Rectangle().fill(theme.sep2).frame(height: 0.5)
            }
            HStack(spacing: 12) {
                Text(key)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.ink3)
                    .frame(width: 56, alignment: .leading)
                Text(value)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.ink2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .lineBox(12)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private func environment(_ svc: ServiceConfig) -> some View {
        if !svc.env.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel(text: "环境变量")
                    .padding(.top, 22)
                    .padding(.bottom, 7)
                    .padding(.horizontal, 4)
                Card {
                    VStack(spacing: 0) {
                        ForEach(Array(svc.env.enumerated()), id: \.offset) { i, e in
                            if i > 0 {
                                Rectangle().fill(theme.sep2).frame(height: 0.5)
                            }
                            HStack(spacing: 14) {
                                Text(e.k)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(theme.blueTx)
                                    .frame(width: 190, alignment: .leading)
                                    .lineLimit(1)
                                Text(e.v)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(theme.ink2)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                        }
                    }
                }
            }
        }
    }
}

// MARK: 日志抽屉

private struct LogDrawer: View {
    let service: ServiceConfig
    @Binding var isOpen: Bool
    @Environment(Store.self) private var store
    @Environment(\.theme) private var theme

    private var lines: [LogLine] {
        let all = store.logs
        let filtered =
            switch store.logMode {
            case .this: all.filter { $0.sid == service.id }
            case .all: all
            case .err: all.filter { $0.lvl == "ERROR" || $0.lvl == "WARN" }
            }
        return filtered.suffix(400)
    }

    var body: some View {
        HStack(spacing: 0) {
            // 拖拽把手
            Capsule()
                .fill(theme.fill2)
                .frame(width: 4, height: 42)
                .frame(width: 16)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
                .help("拖动打开或收起日志")

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("实时日志")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(theme.ink)
                    Spacer()
                    Segmented(
                        options: LogMode.allCases.map { ($0, $0.label) },
                        selection: Binding(get: { store.logMode }, set: { store.logMode = $0 }),
                        font: .system(size: 11.5))
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 8)

                logBody

                HStack(spacing: 10) {
                    Button { store.followLogs.toggle() } label: {
                        Text(store.followLogs ? "跟随最新" : "已暂停")
                            .font(.system(size: 11.5))
                            .foregroundStyle(store.followLogs ? theme.blueTx : theme.ink2)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(store.followLogs ? theme.blueSoft : theme.fill, in: .rect(cornerRadius: 6))
                    }
                    .buttonStyle(Press(scale: 0.96))
                    Text("\(lines.count) 行")
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.ink3)
                    Spacer()
                    Button { store.clearLogs() } label: {
                        Text("清空")
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme.ink3)
                    }
                    .buttonStyle(Press(scale: 0.96))
                }
                .padding(.horizontal, 13)
                .padding(.top, 9)
                .padding(.bottom, 11)
            }
            // 右、下两边伸出容器外被裁掉，描边只留在顶边和左边
            .background {
                let shape = UnevenRoundedRectangle(topLeadingRadius: 12, style: .continuous)
                shape.fill(theme.chrome)
                    .overlay { shape.strokeBorder(theme.sep, lineWidth: 0.5) }
                    .padding([.trailing, .bottom], -1)
            }
            .shadow(color: .black.opacity(0.1), radius: 14, x: -6)
        }
    }

    private var logBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(lines) { l in
                        HStack(alignment: .top, spacing: 8) {
                            Text(Fmt.clock(l.ts))
                                .foregroundStyle(theme.ink3)
                            Text(l.lvl)
                                .foregroundStyle(color(l.lvl))
                                .frame(width: 34, alignment: .leading)
                            Text(l.txt)
                                .foregroundStyle(theme.ink2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 1)
                        .id(l.id)
                    }
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(theme.win)
            .overlay {
                RoundedRectangle(cornerRadius: 9).strokeBorder(theme.sep, lineWidth: 0.5)
            }
            .clipShape(.rect(cornerRadius: 9))
            .padding(.horizontal, 10)
            .onChange(of: lines.last?.id) { _, last in
                guard store.followLogs, let last else { return }
                proxy.scrollTo(last, anchor: .bottom)
            }
            .onChange(of: store.followLogs) { _, on in
                guard on, let last = lines.last?.id else { return }
                proxy.scrollTo(last, anchor: .bottom)
            }
            .onAppear {
                guard let last = lines.last?.id else { return }
                proxy.scrollTo(last, anchor: .bottom)
            }
        }
    }

    private func color(_ level: String) -> Color {
        switch level {
        case "ERROR": theme.redTx
        case "WARN": theme.orangeTx
        default: theme.ink3
        }
    }
}
