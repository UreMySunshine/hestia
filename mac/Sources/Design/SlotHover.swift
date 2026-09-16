import AppKit
import SwiftUI

/// 一排等宽格子的悬停提示。指针由 AppKit 跟踪，只在换到另一格时更新提示框和高亮，
/// 不经过 SwiftUI 的悬停派发
struct SlotHover: NSViewRepresentable {
    let count: Int
    let gap: CGFloat
    /// 第几格的标题与说明
    let text: (Int) -> (title: String, detail: String)

    func makeNSView(context: Context) -> SlotHoverView { SlotHoverView(frame: .zero) }

    func updateNSView(_ v: SlotHoverView, context: Context) {
        v.count = count
        v.gap = gap
        v.text = text
        v.refresh()
    }

    static func dismantleNSView(_ v: SlotHoverView, coordinator: ()) { v.hide() }
}

final class SlotHoverView: NSView {
    var count = 1
    var gap: CGFloat = 0
    var text: (Int) -> (title: String, detail: String) = { _ in ("", "") }

    private let mark = CALayer()
    private let tip = TipPanel()
    private var index: Int?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        // macOS 14 起不裁剪的视图 visibleRect 不受自身边界限制，跟踪区域会铺满整片可视区
        clipsToBounds = true
        mark.cornerRadius = 2.5
        mark.borderWidth = 1.5
        mark.isHidden = true
        layer?.addSublayer(mark)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                owner: self))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { hide() }
    }

    override func mouseEntered(with event: NSEvent) { track(event) }
    override func mouseMoved(with event: NSEvent) { track(event) }
    override func mouseExited(with event: NSEvent) { hide() }

    /// 数据刷新时，停留中的提示跟着更新
    func refresh() {
        if index != nil { show() }
    }

    func hide() {
        index = nil
        mark.isHidden = true
        tip.dismiss()
    }

    private var pitch: CGFloat {
        (bounds.width + gap) / CGFloat(max(count, 1))
    }

    private func slot(_ i: Int) -> CGRect {
        CGRect(x: CGFloat(i) * pitch, y: 0, width: pitch - gap, height: bounds.height)
    }

    private func track(_ event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard bounds.contains(p) else { return hide() }
        let i = min(max(Int(p.x / pitch), 0), count - 1)
        guard i != index else { return }
        index = i
        show()
    }

    private func show() {
        guard let i = index, i < count, let window else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mark.frame = slot(i)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            mark.borderColor = NSColor.labelColor.withAlphaComponent(0.45).cgColor
        }
        mark.isHidden = false
        CATransaction.commit()

        let (title, detail) = text(i)
        let anchor = window.convertToScreen(convert(slot(i), to: nil))
        tip.present(title: title, detail: detail, above: anchor, in: window)
    }
}

/// 深色单行提示框。不接收鼠标、不抢焦点，作为子窗口跟随主窗口
private final class TipPanel: NSPanel {
    private let label = NSTextField(labelWithString: "")
    private static let pad = NSSize(width: 10, height: 6)

    init() {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
            defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true
        hidesOnDeactivate = false

        let back = NSView()
        back.wantsLayer = true
        back.layer?.backgroundColor = NSColor(white: 0.13, alpha: 0.94).cgColor
        back.layer?.cornerRadius = 8
        back.addSubview(label)
        contentView = back
    }

    func present(title t: String, detail d: String, above anchor: NSRect, in parent: NSWindow) {
        let text = NSMutableAttributedString(
            string: t,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12).withMonospacedDigits(),
                .foregroundColor: NSColor(white: 1, alpha: 0.6),
            ])
        text.append(
            NSAttributedString(
                string: "  \(d)",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                    .foregroundColor: NSColor.white,
                ]))
        label.attributedStringValue = text
        let fit = label.fittingSize
        label.frame = NSRect(origin: NSPoint(x: Self.pad.width, y: Self.pad.height), size: fit)
        let size = NSSize(width: fit.width + Self.pad.width * 2, height: fit.height + Self.pad.height * 2)

        // 居中放在格子上方，不超出主窗口左右两边
        var x = anchor.midX - size.width / 2
        x = min(max(x, parent.frame.minX + 8), parent.frame.maxX - size.width - 8)
        setFrame(NSRect(x: x, y: anchor.maxY + 6, width: size.width, height: size.height), display: true)
        if self.parent !== parent {
            self.parent?.removeChildWindow(self)
            parent.addChildWindow(self, ordered: .above)
        }
        orderFront(nil)
        invalidateShadow()
    }

    func dismiss() {
        parent?.removeChildWindow(self)
        orderOut(nil)
    }
}

private extension NSFont {
    func withMonospacedDigits() -> NSFont {
        let d = fontDescriptor.addingAttributes([
            .featureSettings: [
                [
                    NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                    NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector,
                ]
            ]
        ])
        return NSFont(descriptor: d, size: pointSize) ?? self
    }
}
