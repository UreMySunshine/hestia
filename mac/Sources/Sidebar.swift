import SwiftUI

struct Sidebar: View {
    let onNew: () -> Void
    @Environment(Store.self) private var store
    @Environment(\.theme) private var theme

    private let nav: [(screen: Screen, path: String, label: String, tint: Color)] = [
        (.overview, UIIcon.grid, "总览", Color(hex: 0x0A7CFF)),
        (.monitor, ServiceIcon.paths["pulse"]!, "监控", Color(hex: 0x34C759)),
        (.settings, UIIcon.cog, "设置", Color(hex: 0x8E8E93)),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand

            VStack(alignment: .leading, spacing: 2) {
                ForEach(nav, id: \.screen) { item in
                    NavRow(
                        path: item.path,
                        label: item.label,
                        tint: item.tint,
                        active: isActive(item.screen)
                    ) {
                        store.screen = item.screen
                    }
                }
            }
            .padding(.horizontal, 10)

            header
            serviceList
        }
        // 顶部让出交通灯所在的一行
        .padding(.top, Chrome.rowHeight - Chrome.inset + 2)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// 应用图标与名称，与 Dock 里是同一张图
    private var brand: some View {
        HStack(spacing: 11) {
            if let img = NSImage(named: "app-icon") {
                Image(nsImage: img)
                    .resizable()
                    .frame(width: 38, height: 38)
                    .clipShape(.rect(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10).strokeBorder(theme.sep, lineWidth: 0.5)
                    }
            }
            Text("Hestia")
                .font(.system(size: 16, weight: .semibold))
                .tracking(-0.16)
                .foregroundStyle(theme.ink)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    private func isActive(_ s: Screen) -> Bool {
        s == store.screen || (s == .overview && store.screen == .detail)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("服务")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.ink3)
            Spacer()
            Text("\(store.runningCount)/\(store.services.count)")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(theme.ink3)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var serviceList: some View {
        if store.services.isEmpty {
            Button(action: onNew) {
                HStack(spacing: 7) {
                    Glyph(path: UIIcon.plus, lineWidth: 2)
                        .foregroundStyle(theme.blue)
                        .frame(width: 13, height: 13)
                    Text("添加第一个服务")
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme.blue)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .contentShape(.rect)
            }
            .buttonStyle(Press(scale: 0.97))
            .padding(.horizontal, 10)
        } else {
            ServiceList()
        }
    }
}

@Observable
private final class DragState {
    var id: String?
    var origin: Int?
    var slot: Int?
    /// 本轮按压是否已经构成拖拽。松手时按钮与手势都会收到事件，先后顺序不定，
    /// 靠它把「拖完松手」和「单击」区分开
    @ObservationIgnored var dragged = false

    func clear() {
        id = nil
        origin = nil
        slot = nil
    }
}

/// 可拖拽排序的服务列表。
///
/// 不用 SwiftUI 的 `List`：它在 macOS 上是 NSTableView，即使没有任何数据变化也会在每个
/// 显示周期重排整棵视图树，实测持续占掉约 13% 的单核。行高固定，拖拽落点直接算得出来。
private struct ServiceList: View {
    @Environment(Store.self) private var store
    @State private var drag = DragState()

    /// 行高 28 加上行距 2
    private let pitch: CGFloat = 30

    var body: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(Array(store.services.enumerated()), id: \.element.id) { index, svc in
                    ServiceRow(
                        svc: svc,
                        active: store.screen == .detail && store.selection == svc.id,
                        onOpen: { open(svc) },
                        onPort: openPort)
                        .opacity(drag.id == svc.id ? 0.3 : 1)
                        .simultaneousGesture(gesture(svc, at: index))
                }
            }
            // 拖拽期间列表一动不动，只画一条插入位置线。让被跨过的行逐个挪位看着更顺，
            // 但每跨一行就有整列在动画里连续重绘，代价高得多
            .overlay(alignment: .top) { DropLine(drag: drag, pitch: pitch) }
            .padding(.horizontal, 6)
            .padding(.bottom, 10)
        }
        .scrollIndicators(.never)
        .edgeFade()
    }

    /// 拖完松手时按钮也会触发，这里拦掉
    private func open(_ svc: ServiceConfig) {
        guard !drag.dragged else { return }
        store.open(svc.id)
    }

    private func openPort(_ port: UInt16) {
        guard !drag.dragged else { return }
        NSWorkspace.shared.open(URL(string: "http://localhost:\(port)")!)
    }

    private func gesture(_ svc: ServiceConfig, at index: Int) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { g in
                if drag.id == nil {
                    drag.id = svc.id
                    drag.origin = index
                    drag.dragged = true
                    PointerCursor.override = .closedHand
                }
                let slot = min(
                    max(index + Int((g.translation.height / pitch).rounded()), 0),
                    store.services.count - 1)
                if drag.slot != slot { drag.slot = slot }
            }
            .onEnded { _ in
                if let from = drag.origin, let to = drag.slot, to != from {
                    var ids = store.services.map(\.id)
                    ids.insert(ids.remove(at: from), at: to)
                    store.reorder(ids)
                }
                drag.clear()
                PointerCursor.override = nil
                // 按钮的动作可能晚于这里，等下一轮再放开
                DispatchQueue.main.async { drag.dragged = false }
            }
    }
}

/// 插入位置线。只读落点，落点变化才重画
private struct DropLine: View {
    let drag: DragState
    let pitch: CGFloat

    var body: some View {
        if let from = drag.origin, let slot = drag.slot, slot != from {
            Capsule()
                .fill(Color.accentColor)
                .frame(height: 2)
                // 线画在两行之间的行距里；第一行上方没有行距，贴着顶边画，否则会被滚动区域裁掉
                .offset(y: max(0, CGFloat(slot > from ? slot + 1 : slot) * pitch - 3))
        }
    }
}

/// 导航项。图标放在彩色圆角方块里；选中时整行填蓝，方块反白以免与底色混在一起
private struct NavRow: View {
    let path: String
    let label: String
    let tint: Color
    let active: Bool
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 5.5)
                    .fill(active ? .white : tint)
                    .frame(width: 20, height: 20)
                    .overlay {
                        Glyph(path: path, lineWidth: 2)
                            .foregroundStyle(active ? tint : .white)
                            .frame(width: 13, height: 13)
                    }
                Text(label)
                    .font(.system(size: 13, weight: active ? .medium : .regular))
                    .foregroundStyle(active ? .white : theme.ink)
                    .lineBox(13)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(active ? theme.blue : .clear, in: .rect(cornerRadius: 7))
            .hoverHighlight(radius: 7)
            .contentShape(.rect)
        }
        .buttonStyle(Press(scale: 0.985))
    }
}

private struct ServiceRow: View {
    let svc: ServiceConfig
    let active: Bool
    let onOpen: () -> Void
    let onPort: (UInt16) -> Void
    @Environment(Store.self) private var store
    @Environment(\.theme) private var theme

    var body: some View {
        let port = store.port(svc)
        HStack(spacing: 0) {
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    badge
                    Text(svc.name)
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .lineBox(12.5)
                    Spacer(minLength: 4)
                }
                .padding(.leading, 10)
                .padding(.trailing, port == nil ? 8 : 0)
                .padding(.vertical, 5)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            // 运行中时端口单独可点，用浏览器打开本机上的这个端口；未运行时只显示配置值
            if let port {
                let label = Text(String(port))
                    .font(.system(size: 11, design: .monospaced).monospacedDigit())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                if store.brief(svc.id).state == .running {
                    Button { onPort(port) } label: {
                        label
                            .foregroundStyle(theme.blueTx)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help("在浏览器打开 http://localhost:\(port)")
                } else {
                    label.foregroundStyle(theme.ink3)
                }
            }
        }
        .background(active ? theme.fill2 : .clear, in: .rect(cornerRadius: 7))
        .hoverHighlight(radius: 7)
        .contextMenu {
            Button(store.phase(svc.id).up ? "停止" : "启动") { store.toggle(svc.id) }
            Button("重启") { store.restart(svc.id) }
            Divider()
            Button("删除", role: .destructive) { store.delete(svc.id) }
        }
    }

    /// 服务类型图标，右下角的圆点表示运行状态。图标不随状态变淡，状态只看圆点；
    /// 圆点外圈取行底色，把圆点与图标隔开
    private var badge: some View {
        IconBadge(ic: svc.ic, side: 18, glyph: 11)
            .overlay(alignment: .bottomTrailing) {
                Dot(phase: store.phase(svc.id), size: 6)
                    .padding(1.5)
                    .background {
                        ZStack {
                            Circle().fill(theme.card)
                            if active { Circle().fill(theme.fill2) }
                        }
                    }
                    .offset(x: 3, y: 3)
            }
    }
}
