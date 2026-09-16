import SwiftUI

struct Monitor: View {
    @Environment(Store.self) private var store
    @Environment(\.theme) private var theme

    @State private var scrolled = false

    static let headHeight: CGFloat = 30
    static let rowHeight: CGFloat = 40
    /// 可滚动几列的总宽：各列宽、列间距与右侧留白之和
    private static let restWidth: CGFloat = 104 + 104 + 84 + 64 + 120 + 12 * 4 + 14

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

    /// 内存条的满刻度取本表峰值，同一屏内横向可比；下限 64MB 免得小进程被放大
    private func memScale(_ rows: [Row]) -> Double {
        Swift.max(rows.map(\.mem).max() ?? 0, 64)
    }

    /// 服务、状态两列固定，其余列横向滚动。整行的底色、悬停与分隔线铺在两段背后，按固定行高对齐
    private var table: some View {
        let rows = rows
        let scale = memScale(rows)
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
                            .hoverHighlight()
                    }
                }

                HStack(alignment: .top, spacing: 0) {
                    column(rows) {
                        cell("服务", 180)
                        cell("状态", 72)
                    } cell: { MonitorRow(row: $0, part: .lead, memScale: scale) }
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
                            cell("CPU", 104)
                            cell("内存", 104)
                            cell("趋势", 84)
                            cell("端口", 64)
                            Text("错误").frame(minWidth: 120, alignment: .leading)
                        } cell: { MonitorRow(row: $0, part: .rest, memScale: scale) }
                            .padding(.trailing, 14)
                            // 可视区比各列宽时铺满可视区，各列靠左排列
                            .containerRelativeFrame(.horizontal, alignment: .leading) { w, _ in
                                max(w, Self.restWidth)
                            }
                    }
                    .modifier(ScrollFlag(scrolled: $scrolled))
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
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
    let memScale: Double
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
            Spacer(minLength: 0)
        }
        .frame(width: 180, alignment: .leading)

        HStack(spacing: 6) {
            Dot(phase: row.phase, size: 6)
            Text(row.phase.label)
                .font(.system(size: 11.5))
                .foregroundStyle(theme.text(row.phase))
            Spacer(minLength: 0)
        }
        .frame(width: 72, alignment: .leading)
    }

    @ViewBuilder
    private var rest: some View {
        // CPU 满刻度是单核 100%，超过说明进程树用掉不止一个核；内存满刻度是本表峰值
        meter(
            String(format: "%.1f%%", row.cpu),
            row.cpu / 100, theme.blue, labelWidth: 52)
        meter(
            "\(Int(row.mem.rounded()))M",
            row.mem / memScale, theme.teal, labelWidth: 48)

        Spark(
            values: row.series, max: nil, floor: 25,
            line: row.state == .running ? theme.blue : theme.dim,
            fill: row.state == .running ? theme.blue.opacity(0.11) : .clear,
            lineWidth: 1.5
        )
        .frame(width: 84, height: 24)
        .opacity(store.prefs.quiet && row.state != .running ? 0 : 1)

        Text(row.port.map(String.init) ?? "—")
            .font(.system(size: 11.5, design: .monospaced))
            .foregroundStyle(theme.ink2)
            .frame(width: 64, alignment: .leading)

        // 列宽放不下错误原文，只显示累计条数，原文悬停可见，详情页有完整日志
        Text(row.errors > 0 ? "\(row.errors) 条" : "无")
            .font(.system(size: 11.5))
            .foregroundStyle(row.errors > 0 ? theme.redTx : theme.ink3)
            .lineLimit(1)
            .frame(minWidth: 120, alignment: .leading)
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

    private func meter(_ label: String, _ ratio: Double, _ color: Color, labelWidth: CGFloat)
        -> some View
    {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 12.5).monospacedDigit())
                .foregroundStyle(theme.ink2)
                .frame(width: labelWidth, alignment: .leading)
            Bar(value: ratio, color: color)
        }
        .frame(width: 104)
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
