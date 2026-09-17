import SwiftUI

struct ContentView: View {
    @Environment(Store.self) private var store
    @Environment(\.theme) private var theme
    @Environment(\.openWindow) private var openWindow
    @State private var editing: ServiceConfig?
    @State private var editingFlow: Workflow?
    @State private var paletteOpen = false

    var body: some View {
        @Bindable var store = store
        HStack(alignment: .top, spacing: 0) {
            Card(radius: Chrome.sidebarRadius) {
                Sidebar(
                    onNew: { editing = .blank() },
                    onNewWorkflow: { editingFlow = .blank() },
                    onEditWorkflow: { editingFlow = $0 })
            }
            .frame(width: 218)
            .padding([.leading, .vertical], Chrome.inset)

            // 右侧整列贴到窗口边缘，留白由各屏放进自己的滚动内容里。
            // 工具按钮浮在右上角，各屏的标题与它同在最上面一行
            ZStack(alignment: .topTrailing) {
                ZStack(alignment: .topLeading) {
                    screen
                        .id(store.screen)
                        .modifier(ViewIn())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                ChromeBar(
                    onNew: { editing = .blank() },
                    onPalette: { paletteOpen = true })
                    .padding(.top, Chrome.inset)
            }
            .sheet(item: $editingFlow) { wf in
                WorkflowForm(
                    draft: wf,
                    isNew: store.workflow(wf.id) == nil,
                    onSave: { saved in
                        store.save(saved)
                        store.openWorkflow(saved.id)
                    },
                    onDelete: { store.deleteWorkflow(wf.id) })
                .environment(store)
                .preferredColorScheme(store.appearance.scheme)
                .themed()
            }
        }
        .background(theme.page)
        // 隐藏标题栏仍会留出安全区，内容要顶到窗口上沿，交通灯落在侧边栏顶部的留白里
        .ignoresSafeArea(.container, edges: .top)
        .background(WindowReader { TrafficLights.attach(to: $0) })
        .overlay {
            if paletteOpen {
                CommandPalette(isOpen: $paletteOpen, onEditWorkflow: { editingFlow = $0 })
            }
        }
        .sheet(item: $editing) { svc in
            ServiceForm(draft: svc, isNew: store.service(svc.id) == nil) { saved in
                store.save(saved)
                store.open(saved.id)
            }
            .environment(store)
            .preferredColorScheme(store.appearance.scheme)
            .themed()
        }
        .onAppear { MainWindow.reopen = { openWindow(id: MainWindow.id) } }
        .background {
            // 命令面板的快捷键。菜单项会抢走 ⌘K，所以挂一个隐藏按钮接住
            Button("") { paletteOpen.toggle() }
                .keyboardShortcut("k", modifiers: .command)
                .opacity(0)
        }
    }

    @ViewBuilder
    private var screen: some View {
        switch store.screen {
        case .overview:
            Overview(onEdit: { editing = $0 })
        case .detail:
            Detail(onEdit: { editing = $0 })
        case .workflow:
            WorkflowDetail(onEdit: { editingFlow = $0 })
        case .monitor:
            Monitor()
        case .settings:
            Settings()
        }
    }
}

/// 右侧内容区顶部的工具按钮，与交通灯同一条中线
struct ChromeBar: View {
    let onNew: () -> Void
    let onPalette: () -> Void
    @Environment(Store.self) private var store
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 6)

            Button(action: onPalette) {
                Text("⌘K")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.ink2)
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .background(theme.fill, in: .rect(cornerRadius: 7))
            }
            .buttonStyle(Press(scale: 0.96))
            .help("命令面板 ⌘K")

            ChromeButton(path: UIIcon.plus, help: "新建服务", tint: theme.blue, action: onNew)

            Button {
                store.appearance = store.appearance == .dark ? .light : .dark
            } label: {
                Text(store.appearance == .dark ? "☀" : "☾")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.ink2)
                    .frame(width: 28, height: 26)
                    .background(theme.fill, in: .rect(cornerRadius: 7))
            }
            .buttonStyle(Press())
            .help("切换外观")
        }
        // 右沿与内容卡片对齐
        .padding(.trailing, Chrome.gutter)
        // 这一行从窗口留白之下开始，减去留白后按钮中线正好落在交通灯中线上
        .frame(height: (Chrome.rowHeight / 2 - Chrome.inset) * 2)
    }
}
