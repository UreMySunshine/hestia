import AppKit
import SwiftUI

@main
struct HestiaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = Store()

    var body: some Scene {
        WindowGroup(id: MainWindow.id) {
            ContentView()
                .environment(store)
                .frame(minWidth: 1_000, minHeight: 680)
                .preferredColorScheme(store.appearance.scheme)
                .themed()
                .onAppear {
                    guard delegate.store == nil else { return }
                    delegate.store = store
                    store.boot()
                    delegate.menuBar = MenuBarController(store: store)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1_180, height: 780)
        .commands { AppCommands(store: store) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var store: Store?
    var menuBar: MenuBarController?

    /// 关掉主窗口只是收起，被托管的进程继续运行
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag, MainWindow.reopen != nil else { return true }
        showMainWindow()
        // 已经自行重开，返回 true 会让系统再按默认场景另开一个
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        store?.shutdown()
    }
}

/// 主窗口场景。关掉窗口后场景内容会被销毁，只能经 SwiftUI 的 `openWindow` 重开
@MainActor
enum MainWindow {
    static let id = "main"
    static var reopen: (() -> Void)?
}

/// 把主窗口调到前台；已关掉则重新打开
@MainActor
func showMainWindow() {
    NSApp.activate()
    if let w = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain && !($0 is NSPanel) }) {
        w.makeKeyAndOrderFront(nil)
    } else {
        MainWindow.reopen?()
    }
}

struct AppCommands: Commands {
    let store: Store

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandMenu("服务") {
            Button("全部启动") { store.startAll() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Button("全部停止") { store.stopAll() }
                .keyboardShortcut(".", modifiers: [.command, .shift])
            Button("开关日志抽屉") { store.drawerOpen.toggle() }
                .keyboardShortcut("l", modifiers: .command)
            Button("切换深浅色") {
                store.appearance = store.appearance == .dark ? .light : .dark
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            Divider()
            Button("总览") { store.screen = .overview }
                .keyboardShortcut("1", modifiers: .command)
            Button("监控") { store.screen = .monitor }
                .keyboardShortcut("2", modifiers: .command)
            Button("设置") { store.screen = .settings }
                .keyboardShortcut("3", modifiers: .command)
        }
    }
}
