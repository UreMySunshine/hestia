import SwiftUI

struct ContentView: View {
    @Environment(Store.self) private var store
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openWindow) private var openWindow
    @State private var editing: ServiceConfig?
    @State private var editingFlow: Workflow?
    @State private var paletteOpen = false

    var body: some View {
        @Bindable var store = store
        HStack(alignment: .top, spacing: 0) {
            Sidebar(onNew: { editing = .blank() }, onEditWorkflow: { editingFlow = $0 })
                .frame(width: 218)
                .clipShape(.rect(cornerRadius: Chrome.sidebarRadius))
                // 玻璃垫在背景层，侧栏内容照原样绘制；直接加在内容上，图标的灰阶过渡会被压掉。
                // 深色的玻璃自带压暗，比右侧暗一截，用浅色着色提亮
                .background {
                    Color.clear.glassEffect(
                        .regular.tint(scheme == .dark ? .white.opacity(0.1) : nil),
                        in: .rect(cornerRadius: Chrome.sidebarRadius))
                }
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
                    onNewWorkflow: { editingFlow = .blank(among: store.workflows) },
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
        // 窗口底透出桌面，侧栏玻璃才有东西可折射。深色用厚一档的材质再压暗一层，
        // 否则亮壁纸透上来，灰色文字看不清
        .background(scheme == .dark ? Color.black.opacity(0.25) : .clear)
        .containerBackground(scheme == .dark ? .thickMaterial : .thinMaterial, for: .window)
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
    let onNewWorkflow: () -> Void
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
                    .padding(.horizontal, 11)
                    .frame(height: 28)
                    .glassFace()
            }
            .buttonStyle(Press(scale: 0.96))
            .help("命令面板 ⌘K")

            ChromeButton(
                path: UIIcon.plus, help: "新建服务或工作流", tint: theme.blue,
                menu: { [.item("新建服务", action: onNew), .item("新建工作流", action: onNewWorkflow)] })

            Button {
                store.appearance = store.appearance == .dark ? .light : .dark
            } label: {
                Text(store.appearance == .dark ? "☀" : "☾")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.ink2)
                    .frame(width: 28, height: 28)
                    .glassFace(in: Circle())
            }
            .buttonStyle(Press())
            .help("切换外观")
            // 外观从深色切回浅色后，这颗按钮的玻璃会停在深色上，按外观重建
            .id(store.appearance)
        }
        // 右沿与内容卡片对齐
        .padding(.trailing, Chrome.gutter)
        // 这一行从窗口留白之下开始，减去留白后按钮中线正好落在交通灯中线上
        .frame(height: (Chrome.rowHeight / 2 - Chrome.inset) * 2)
    }
}
