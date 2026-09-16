import AppKit
import SwiftUI

/// 菜单栏图标与下拉面板。
///
/// 不用 SwiftUI 的 `MenuBarExtra`：它的 label 每次换图都要重建状态项的宿主视图，
/// 火箭动画一秒换六帧，实测持续占掉约 8% 的单核。自建 `NSStatusItem` 后换图只是一次赋值。
/// 面板用无边框窗口而非 `NSPopover`，后者必定带指向箭头。
@MainActor
final class MenuBarController {
    /// 面板与菜单栏之间的间距
    private static let gap: CGFloat = 6
    private static let corner: CGFloat = 12
    /// 每帧停留时长
    private static let frameInterval: TimeInterval = 0.17

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel = PanelWindow()
    private let store: Store

    private let idle: NSImage
    private let frames: [NSImage]
    private var step = 0
    private var showingIdle = true
    private var timer: Timer?
    private var watchers: [Any] = []

    init(store: Store) {
        self.store = store
        idle = MenuBarController.load("tray-idle")
        frames = (1...5).map { MenuBarController.load("tray-run-\($0)") }

        let host = NSHostingView(
            rootView: MenuBarPanel()
                .environment(store)
                .preferredColorScheme(store.appearance.scheme)
                .themed())
        host.translatesAutoresizingMaskIntoConstraints = false

        let back = NSVisualEffectView()
        back.material = .popover
        back.blendingMode = .behindWindow
        back.state = .active
        back.maskImage = .roundedMask(Self.corner)
        back.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: back.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: back.trailingAnchor),
            host.topAnchor.constraint(equalTo: back.topAnchor),
            host.bottomAnchor.constraint(equalTo: back.bottomAnchor),
        ])
        panel.contentView = back

        item.button?.image = idle
        item.button?.target = self
        item.button?.action = #selector(click)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.toolTip = "Hestia"

        let t = Timer(timeInterval: Self.frameInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    deinit { timer?.invalidate() }

    private func advance() {
        guard store.runningCount > 0 else {
            if !showingIdle {
                item.button?.image = idle
                showingIdle = true
                step = 0
            }
            return
        }
        item.button?.image = frames[step % frames.count]
        step += 1
        showingIdle = false
    }

    // MARK: 交互

    @objc private func click() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else if panel.isVisible {
            close()
        } else {
            open()
        }
    }

    private func showMenu() {
        close()
        let menu = NSMenu()
        menu.addItem(entry("打开主窗口", #selector(openMain)))
        menu.addItem(.separator())
        menu.addItem(entry("退出 Hestia", #selector(quit)))
        guard let button = item.button else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 4), in: button)
    }

    private func entry(_ title: String, _ action: Selector) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: "")
        mi.target = self
        return mi
    }

    @objc private func openMain() {
        showMainWindow()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func open() {
        guard let button = item.button, let bar = button.window, let back = panel.contentView
        else { return }
        panel.appearance = store.appearance.scheme.map {
            NSAppearance(named: $0 == .dark ? .darkAqua : .aqua)
        } ?? nil

        let size = back.fittingSize
        panel.setContentSize(size)
        let anchor = bar.convertToScreen(button.convert(button.bounds, to: nil))
        let limit = (bar.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let x = min(max(anchor.midX - size.width / 2, limit.minX + 8), limit.maxX - size.width - 8)
        panel.setFrameOrigin(NSPoint(x: x, y: anchor.minY - size.height - Self.gap))
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.invalidateShadow()
        watch()
    }

    private func close() {
        watchers.forEach(NSEvent.removeMonitor)
        watchers = []
        panel.orderOut(nil)
    }

    /// 点面板和状态项之外的任何地方，或按下退出键，都收起面板
    private func watch() {
        let outside = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] e in
            guard let self else { return e }
            if e.window !== self.panel && e.window !== self.item.button?.window { self.close() }
            return e
        }
        let elsewhere = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        let esc = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] e in
            guard let self, e.keyCode == 53 else { return e }
            self.close()
            return nil
        }
        watchers = [outside, elsewhere, esc].compactMap { $0 }
    }

    /// 状态栏把图标限制在 18pt 高，尺寸按点写死，位图本身是 2 倍图
    private static func load(_ name: String) -> NSImage {
        let img = Bundle.main.image(forResource: name) ?? NSImage(size: NSSize(width: 17, height: 18))
        img.size = NSSize(width: 17, height: 18)
        img.isTemplate = false
        return img
    }
}

/// 无边框窗口默认不能成为主键窗口，面板里的控件收不到点击
final class PanelWindow: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 296, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovable = false
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { true }
}
