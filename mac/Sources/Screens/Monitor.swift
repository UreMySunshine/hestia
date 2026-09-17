import SwiftUI

struct Monitor: View {
    @Environment(Store.self) private var store
    @Environment(\.theme) private var theme

    @State private var scrolled = false
    @State private var tableWidth: CGFloat = 0

    static let headHeight: CGFloat = 30
    static let rowHeight: CGFloat = 40

    /// 各列宽度。表格比各列最小宽度之和宽时，多出的部分按比例分给各列；
    /// 窄时保持最小宽度，右侧几列横向滚动
    struct Columns {
        var name: CGFloat = 180
        var state: CGFloat = 72
        var cpu: CGFloat = 64
        var mem: CGFloat = 76
        var trend: CGFloat = 84
        var port: CGFloat = 64
        var errors: CGFloat = 120

        /// 固定两列连同左右内边距与列间距
        var leadWidth: CGFloat { 14 + name + 12 + state + 12 }
        /// 可滚动几列连同列间距与右侧留白
        var restWidth: CGFloat { cpu + mem + trend + port + errors + 12 * 4 + 14 }

        func fitting(_ width: CGFloat) -> Columns {
            let extra = width - leadWidth - restWidth
            guard extra > 0 else { return self }
            let grow = { (w: CGFloat, share: CGFloat) in (w + extra * share).rounded(.down) }
            var c = self
            c.name = grow(name, 0.3)
            c.state = grow(state, 0.1)
            c.cpu = grow(cpu, 0.1)
            c.mem = grow(mem, 0.1)
            c.trend = grow(trend, 0.25)
            c.port = grow(port, 0.1)
            c.errors = grow(errors, 0.05)
            return c
        }
    }

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 0) {
            PageTitle(text: "监控", detail: subtitle)

            HStack(spacing: 10) {
                Segmented(
                    options: StateFilter.allCases.map { ($0, "\($0.rawValue) \(store.count($0))") },
                    selection: $store.monitorFilter,
                    font: .system(size: 11.5))
                Spacer(minLength: 8)
                SearchBox(placeholder: "搜索服务或端口", text: $store.monitorQuery)
                    .frame(width: 200)
                Segmented(
                    options: MonitorSort.allCases.map { ($0, $0.rawValue) },
                    selection: $store.monitorSort,
                    font: .system(size: 11.5))
                    .help(store.monitorSort.help)
            }
            .padding(.horizontal, Chrome.gutter)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    table
                    alerts
                }
                .padding(.horizontal, Chrome.gutter)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.never)
            .edgeFade()
        }
    }

    private var subtitle: String {
        "\(store.services.count) 个服务 · CPU \(Int(store.totalCpu.rounded()))% · 内存 \(String(format: "%.1f", store.totalMem / 1024)) GB"
    }

    private var rows: [Row] {
        let q = store.monitorQuery.trimmingCharacters(in: .whitespaces).lowercased()
        var out = store.services
            .filter { store.monitorFilter.accepts(store.status($0.id).state) }
            .filter { svc in
                guard !q.isEmpty else { return true }
                let port = store.port(svc).map(String.init) ?? ""
                return svc.name.lowercased().contains(q) || port.contains(q)
            }
            .map { svc in
                let st = store.status(svc.id)
                return Row(
                    id: svc.id, name: svc.name, ic: svc.ic, isSelf: false,
                    state: st.state, phase: store.phase(svc.id), cpu: st.cpu, mem: st.mem,
                    errors: st.errors, lastError: st.lastError,
                    port: st.ports.first ?? (svc.port == 0 ? nil : svc.port),
                    series: store.cpuSeries(svc.id))
            }
        switch store.monitorSort {
        case .none: break
        case .cpu: out.sort { $0.cpu > $1.cpu }
        case .mem: out.sort { $0.mem > $1.mem }
        case .name: out.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        // 应用自身固定排在末尾，用来对比托管进程与 Hestia 本身的开销
        if (store.monitorFilter == .all || store.monitorFilter == .running), q.isEmpty || "hestia".contains(q) {
            out.append(
                Row(
                    id: "__self", name: "Hestia", ic: "pulse", isSelf: true,
                    state: .running, phase: .running, cpu: store.own.cpu, mem: store.own.mem,
                    errors: 0, lastError: "", port: nil, series: store.selfHist))
        }
        return out
    }

    /// 服务、状态两列固定，其余列横向滚动。整行的底色、悬停与分隔线铺在两段背后，按固定行高对齐
    private var table: some View {
        let rows = rows
        let cols = Columns().fitting(tableWidth)
        return Card {
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    Color.clear.frame(height: Self.headHeight)
                    Rectangle().fill(theme.sep).frame(height: 0.5)
                    if rows.isEmpty {
                        Text("没有符合条件的进程")
                            .font(.system(size: 12.5))
                            .foregroundStyle(theme.ink3)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 34)
                    }
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                        if i > 0 {
                            Rectangle().fill(theme.sep2).frame(height: 0.5)
                        }
                        (r.isSelf ? theme.fill : Color.clear)
                            .frame(height: Self.rowHeight)
                            .hoverHighlight(cursor: r.isSelf ? nil : .pointingHand)
                    }
                }

                HStack(alignment: .top, spacing: 0) {
                    column(rows) {
                        cell("服务", cols.name)
                        cell("状态", cols.state)
                    } cell: { MonitorRow(row: $0, part: .lead, cols: cols) }
                        .padding(.leading, 14)
                        .padding(.trailing, 12)
                        // 分隔线的占位色块横向可伸缩，不固定宽度时 HStack 会把多出的宽度分给这一列
                        .fixedSize(horizontal: true, vertical: false)
                        .overlay(alignment: .trailing) {
                            if scrolled {
                                Rectangle().fill(theme.sep).frame(width: 0.5)
                            }
                        }

                    ScrollView(.horizontal, showsIndicators: false) {
                        column(rows) {
                            cell("CPU", cols.cpu)
                            cell("内存", cols.mem)
                            cell("趋势", cols.trend)
                            cell("端口", cols.port)
                            Text("错误").frame(minWidth: cols.errors, alignment: .leading)
                        } cell: { MonitorRow(row: $0, part: .rest, cols: cols) }
                            .padding(.trailing, 14)
                            .containerRelativeFrame(.horizontal, alignment: .leading) { w, _ in
                                max(w, cols.restWidth)
                            }
                    }
                    .modifier(ScrollFlag(scrolled: $scrolled))
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { tableWidth = $0 }
    }

    /// 表头与各行的内容，行距留出分隔线的高度
    private func column<Head: View, Cell: View>(
        _ rows: [Row], @ViewBuilder head: () -> Head, @ViewBuilder cell: @escaping (Row) -> Cell
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) { head() }
                .font(.system(size: 11))
                .foregroundStyle(theme.ink3)
                .frame(height: Self.headHeight)
            Color.clear.frame(height: 0.5)
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                if i > 0 {
                    Color.clear.frame(height: 0.5)
                }
                cell(r).frame(height: Self.rowHeight)
            }
        }
    }

    private func cell(_ text: String, _ width: CGFloat) -> some View {
        Text(text).frame(width: width, alignment: .leading)
    }

    // MARK: 告警

    private var alerts: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "最近告警")
                .padding(.top, 22)
                .padding(.bottom, 7)
                .padding(.horizontal, 4)
            Card {
                VStack(spacing: 0) {
                    ForEach(Array(alertList.enumerated()), id: \.offset) { i, a in
                        if i > 0 {
                            Rectangle().fill(theme.sep2).frame(height: 0.5)
                        }
                        HStack(spacing: 11) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(a.tint)
                                .frame(width: 22, height: 22)
                                .overlay {
                                    Glyph(path: a.glyph, lineWidth: 2.2)
                                        .foregroundStyle(.white)
                                        .frame(width: 13, height: 13)
                                }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(a.title)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(theme.ink)
                                    .lineLimit(1)
                                Text(a.meta)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(theme.ink3)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .contentShape(.rect)
                        .pointerCursor(a.id == nil ? nil : .pointingHand)
                        .onTapGesture { if let id = a.id { store.open(id) } }
                    }
                }
            }
        }
    }

    private struct Alert {
        var id: String?
        var title: String
        var meta: String
        var tint: Color
        var glyph: String
    }

    private var alertList: [Alert] {
        var out: [Alert] = []
        for svc in store.services {
            let st = store.status(svc.id)
            if st.state == .error {
                out.append(
                    Alert(
                        id: svc.id, title: "\(svc.name) 未在运行",
                        meta: st.lastError.isEmpty ? "已重启 \(st.restarts) 次" : st.lastError,
                        tint: theme.red, glyph: UIIcon.warn))
            } else if st.errors > 0 {
                out.append(
                    Alert(
                        id: svc.id, title: "\(svc.name) 累计 \(st.errors) 次异常退出",
                        meta: st.lastError.isEmpty ? "点击查看日志" : st.lastError,
                        tint: theme.orange, glyph: UIIcon.warn))
            }
            if st.state == .running, st.cpu > 50 {
                out.append(
                    Alert(
                        id: svc.id, title: "\(svc.name) CPU 偏高 \(Int(st.cpu.rounded()))%",
                        meta: "占 \(String(format: "%.1f", st.cpu / Double(store.cores)))% 的整机算力",
                        tint: theme.orange, glyph: UIIcon.warn))
            }
        }
        if out.isEmpty {
            out.append(
                Alert(
                    id: nil, title: "暂无告警", meta: "所有服务运行平稳",
                    tint: theme.green, glyph: UIIcon.check))
        }
        return Array(out.prefix(5))
    }

    struct Row: Identifiable {
        var id: String
        var name: String
        var ic: String
        var isSelf: Bool
        var state: RunState
        var phase: Phase
        var cpu: Double
        var mem: Double
        var errors: Int
        var lastError: String
        var port: UInt16?
        var series: [Double]
    }
}

private struct MonitorRow: View {
    enum Part { case lead, rest }

    let row: Monitor.Row
    let part: Part
    let cols: Monitor.Columns
    @Environment(Store.self) private var store
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            switch part {
            case .lead: lead
            case .rest: rest
            }
        }
        .font(.system(size: 12.5))
        .foregroundStyle(theme.ink)
        .frame(maxHeight: .infinity)
        .contentShape(.rect)
        .onTapGesture { if !row.isSelf { store.open(row.id) } }
    }

    @ViewBuilder
    private var lead: some View {
        HStack(spacing: 9) {
            icon
            Text(row.name)
                .lineLimit(1)
                .truncationMode(.tail)
                .lineBox(12.5)
            if row.isSelf {
                Text("本应用")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(theme.blueTx)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(theme.blueSoft, in: .capsule)
                    .fixedSize()
            }
            Spacer(minLength: 0)
        }
        .frame(width: cols.name, alignment: .leading)
        .help(row.isSelf ? "Hestia 自身的进程，不属于托管的服务" : "")

        HStack(spacing: 6) {
            Dot(phase: row.phase, size: 6)
            Text(row.phase.label)
                .font(.system(size: 11.5))
                .foregroundStyle(theme.text(row.phase))
            Spacer(minLength: 0)
        }
        .frame(width: cols.state, alignment: .leading)
    }

    @ViewBuilder
    private var rest: some View {
        figure(String(format: "%.1f%%", row.cpu), width: cols.cpu)
        figure(Fmt.mem(row.mem), width: cols.mem)

        Spark(
            values: row.series, max: nil, floor: 25,
            line: row.state == .running ? theme.blue : theme.dim,
            fill: row.state == .running ? theme.blue.opacity(0.11) : .clear,
            lineWidth: 1.5
        )
        .frame(width: cols.trend, height: 24)
        .opacity(store.prefs.quiet && row.state != .running ? 0 : 1)

        Text(row.port.map(String.init) ?? "—")
            .font(.system(size: 11.5, design: .monospaced))
            .foregroundStyle(theme.ink2)
            .frame(width: cols.port, alignment: .leading)

        // 列宽放不下错误原文，只显示累计条数，原文悬停可见，详情页有完整日志
        Text(row.errors > 0 ? "\(row.errors) 条" : "无")
            .font(.system(size: 11.5))
            .foregroundStyle(row.errors > 0 ? theme.redTx : theme.ink3)
            .lineLimit(1)
            .frame(minWidth: cols.errors, alignment: .leading)
            .help(row.errors > 0 ? row.lastError : "")
    }

    /// 应用自身用真正的 app 图标，和 Dock、关于窗口保持同一个身份
    @ViewBuilder
    private var icon: some View {
        if row.isSelf, let img = NSImage(named: "app-icon") {
            Image(nsImage: img)
                .resizable()
                .frame(width: 22, height: 22)
                .clipShape(.rect(cornerRadius: 6))
        } else {
            IconBadge(ic: row.ic, side: 22, glyph: 13, phase: row.phase)
        }
    }

    private func figure(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 12.5).monospacedDigit())
            .foregroundStyle(theme.ink2)
            .lineLimit(1)
            .frame(width: width, alignment: .leading)
    }
}

/// 横向滚动离开起点时置位，用来在固定列边缘画分隔线。macOS 14 没有滚动几何回调，不画
private struct ScrollFlag: ViewModifier {
    @Binding var scrolled: Bool

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.onScrollGeometryChange(for: Bool.self) { $0.contentOffset.x > 0.5 } action: { _, now in
                scrolled = now
            }
        } else {
            content
        }
    }
}
