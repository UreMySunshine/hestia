import SwiftUI

struct CommandPalette: View {
    @Binding var isOpen: Bool
    @Environment(Store.self) private var store
    @Environment(\.theme) private var theme
    @State private var query = ""
    @State private var cursor = 0
    @FocusState private var focused: Bool

    private struct Item: Identifiable {
        var id: String
        var path: String
        var color: Color
        var label: String
        var hint: String
        var run: () -> Void
    }

    private var items: [Item] {
        var all: [Item] = store.services.map { svc in
            // 与 toggle 的判断一致：启动中也算作要停止
            let running = store.phase(svc.id).up
            return Item(
                id: "svc-\(svc.id)",
                path: running ? UIIcon.stop : UIIcon.play,
                color: running ? theme.redTx : theme.blue,
                label: (running ? "停止 " : "启动 ") + svc.name,
                hint: svc.cmd,
                run: { store.toggle(svc.id) })
        }
        all += store.services.map { svc in
            Item(
                id: "go-\(svc.id)", path: UIIcon.forward, color: theme.ink3,
                label: "打开 " + svc.name, hint: svc.proj,
                run: { store.open(svc.id) })
        }
        all += [
            Item(
                id: "nav-overview", path: UIIcon.grid, color: theme.ink3,
                label: "跳转 · 总览", hint: "⌘1", run: { store.screen = .overview }),
            Item(
                id: "nav-monitor", path: ServiceIcon.path("pulse"), color: theme.ink3,
                label: "跳转 · 监控", hint: "⌘2", run: { store.screen = .monitor }),
            Item(
                id: "nav-settings", path: UIIcon.cog, color: theme.ink3,
                label: "跳转 · 设置", hint: "⌘3", run: { store.screen = .settings }),
            Item(
                id: "start-all", path: UIIcon.bolt, color: theme.blue,
                label: "全部启动", hint: "⇧⌘R", run: { store.startAll() }),
            Item(
                id: "stop-all", path: UIIcon.stop, color: theme.redTx,
                label: "全部停止", hint: "⇧⌘.", run: { store.stopAll() }),
        ]

        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return Array(all.prefix(9)) }
        return Array(
            all.filter {
                $0.label.lowercased().contains(q) || $0.hint.lowercased().contains(q)
            }.prefix(9))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.22)
                .ignoresSafeArea()
                .onTapGesture { isOpen = false }

            VStack(spacing: 0) {
                TextField("启动、停止、跳转…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(theme.ink)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)
                    .background(theme.field, in: .rect(cornerRadius: 9))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9).strokeBorder(theme.sep, lineWidth: 0.5)
                    }
                    .focused($focused)
                    .onSubmit(runCursor)
                    .onChange(of: query) { _, _ in cursor = 0 }

                if !items.isEmpty {
                    VStack(spacing: 1) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                            row(item, active: i == cursor)
                        }
                    }
                    .padding(.top, 6)
                }
            }
            .padding(8)
            .frame(width: 540)
            .background(.regularMaterial, in: .rect(cornerRadius: 13))
            .overlay {
                RoundedRectangle(cornerRadius: 13).strokeBorder(theme.popBorder, lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.3), radius: 32, y: 14)
            .padding(.top, 110)
        }
        .onAppear { focused = true }
        .background {
            // 键盘导航挂在隐藏按钮上，输入框仍然保持焦点
            Group {
                Button("") { move(1) }.keyboardShortcut(.downArrow, modifiers: [])
                Button("") { move(-1) }.keyboardShortcut(.upArrow, modifiers: [])
                Button("") { isOpen = false }.keyboardShortcut(.escape, modifiers: [])
            }
            .opacity(0)
        }
    }

    private func row(_ item: Item, active: Bool) -> some View {
        Button {
            item.run()
            isOpen = false
        } label: {
            HStack(spacing: 11) {
                Glyph(path: item.path, lineWidth: 1.9)
                    .foregroundStyle(active ? .white : item.color)
                    .frame(width: 15, height: 15)
                Text(item.label)
                    .font(.system(size: 13))
                    .foregroundStyle(active ? .white : theme.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(item.hint)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(active ? .white.opacity(0.8) : theme.ink3)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 170, alignment: .trailing)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(active ? theme.blue : .clear, in: .rect(cornerRadius: 8))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { if $0, let i = items.firstIndex(where: { $0.id == item.id }) { cursor = i } }
    }

    private func move(_ delta: Int) {
        guard !items.isEmpty else { return }
        cursor = (cursor + delta + items.count) % items.count
    }

    private func runCursor() {
        guard items.indices.contains(cursor) else { return }
        items[cursor].run()
        isOpen = false
    }
}
