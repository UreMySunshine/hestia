import AppKit
import SwiftUI

/// 窗口外壳的几何常量。交通灯、悬浮侧边栏、右上角工具按钮共用一条中线
enum Chrome {
    /// 窗口四周留白
    static let inset: CGFloat = 12
    /// 交通灯与工具按钮所在一行的高度，二者都在这一行里垂直居中
    static let rowHeight: CGFloat = 56
    /// 关闭按钮距窗口左沿
    static let lightsLeading: CGFloat = 20
    static let sidebarRadius: CGFloat = 14
    /// 右侧内容区的左右留白。放在滚动内容里面而不是外面，卡片阴影才不会被滚动区的边界裁掉
    static let gutter: CGFloat = 16
}

extension NSImage {
    /// 可拉伸的圆角遮罩。材质视图的图层圆角裁不掉模糊背景，只能用遮罩图
    static func roundedMask(_ r: CGFloat) -> NSImage {
        let edge = r * 2 + 1
        let img = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
            return true
        }
        img.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
        img.resizingMode = .stretch
        return img
    }
}

/// 页面大标题，与交通灯、右上角工具按钮同在窗口最上面一行，概要跟在标题右侧
struct PageTitle: View {
    let text: String
    var detail = ""
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(text)
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.55)
                .foregroundStyle(theme.ink)
            Text(detail)
                .font(.system(size: 12.5))
                .foregroundStyle(theme.ink2)
                .lineLimit(1)
        }
        .frame(height: Chrome.rowHeight)
        .padding(.horizontal, Chrome.gutter + 2)
        .padding(.bottom, 4)
    }
}

/// 把 SwiftUI 所在的窗口交出来
struct WindowReader: NSViewRepresentable {
    let configure: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> Probe { Probe(configure) }
    func updateNSView(_ v: Probe, context: Context) {}

    final class Probe: NSView {
        let configure: @MainActor (NSWindow) -> Void

        init(_ configure: @escaping @MainActor (NSWindow) -> Void) {
            self.configure = configure
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { configure(window) }
        }
    }
}

/// 交通灯位置。
///
/// 系统把它们放在 28pt 高的标题栏里，比悬浮侧边栏的上沿还高。做法同 Electron 的
/// `trafficLightPosition`：撑高标题栏容器，按钮在其中垂直居中。系统在缩放、
/// 切换全屏、窗口激活状态变化后会重排按钮，需要重新摆放
@MainActor
enum TrafficLights {
    private static var watched: Set<ObjectIdentifier> = []

    static func attach(to window: NSWindow) {
        place(window)
        guard watched.insert(ObjectIdentifier(window)).inserted else { return }
        let names: [Notification.Name] = [
            NSWindow.didResizeNotification,
            NSWindow.didExitFullScreenNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
        ]
        for name in names {
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) {
                [weak window] _ in
                MainActor.assumeIsolated {
                    if let window { place(window) }
                }
            }
        }
    }

    private static func place(_ window: NSWindow) {
        guard !window.styleMask.contains(.fullScreen),
            let close = window.standardWindowButton(.closeButton),
            let mini = window.standardWindowButton(.miniaturizeButton),
            let zoom = window.standardWindowButton(.zoomButton),
            let container = close.superview?.superview
        else { return }

        let height = Chrome.rowHeight
        var frame = container.frame
        frame.size.height = height
        frame.origin.y = window.frame.height - height
        container.frame = frame

        let step = mini.frame.minX - close.frame.minX
        for (i, button) in [close, mini, zoom].enumerated() {
            button.setFrameOrigin(
                NSPoint(
                    x: Chrome.lightsLeading + CGFloat(i) * step,
                    y: (height - button.frame.height) / 2))
        }
    }
}
