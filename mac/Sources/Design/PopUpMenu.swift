import AppKit
import SwiftUI

/// 弹出菜单里的一项
struct MenuEntry {
    enum Kind {
        case item(() -> Void)
        case header
        case separator
    }

    var title = ""
    /// 第二行的说明文字
    var subtitle = ""
    var subtitleSymbol: String?
    var help: String?
    var checked = false
    var enabled = true
    var kind: Kind

    static func item(
        _ title: String, subtitle: String = "", subtitleSymbol: String? = nil, help: String? = nil,
        checked: Bool = false, enabled: Bool = true,
        action: @escaping () -> Void
    ) -> MenuEntry {
        MenuEntry(title: title, subtitle: subtitle, subtitleSymbol: subtitleSymbol, help: help,
            checked: checked, enabled: enabled, kind: .item(action))
    }

    static func header(_ title: String) -> MenuEntry { MenuEntry(title: title, kind: .header) }

    static let separator = MenuEntry(kind: .separator)
}

/// 点击后在自身下方弹出系统菜单。
///
/// SwiftUI 的 `Menu` 在 macOS 上只认文字和系统图标作为标签，放不进自绘的图标与底色，
/// 这里用普通按钮承载标签，菜单交给 `NSMenu`
struct PopUpMenu<Label: View>: View {
    let entries: () -> [MenuEntry]
    @ViewBuilder var label: () -> Label
    @State private var anchor = MenuAnchor()

    var body: some View {
        Button(action: show, label: label)
            .background(AnchorView(anchor: anchor))
    }

    private func show() {
        guard let view = anchor.view else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let target = MenuTarget()
        menu.delegate = target
        for e in entries() {
            switch e.kind {
            case .separator:
                menu.addItem(.separator())
            case .header:
                menu.addItem(.sectionHeader(title: e.title))
            case .item(let action):
                let item = NSMenuItem(title: e.title, action: #selector(MenuTarget.run(_:)), keyEquivalent: "")
                item.target = target
                item.tag = target.actions.count
                item.state = e.checked ? .on : .off
                item.isEnabled = e.enabled
                item.toolTip = e.help
                let title = NSMutableAttributedString(string: item.title, attributes: [
                    .foregroundColor: NSColor.labelColor,
                    .font: NSFont.menuFont(ofSize: 0),
                ])
                if !e.subtitle.isEmpty {
                    title.append(NSAttributedString(string: "\n"))
                    if let icon = e.subtitleSymbol {
                        let attachment = NSTextAttachment()
                        attachment.image = symbol(icon, color: .secondaryLabelColor)
                        attachment.bounds = NSRect(x: 0, y: -2, width: 12, height: 12)
                        title.append(NSAttributedString(attachment: attachment))
                        title.append(NSAttributedString(string: " "))
                    }
                    title.append(NSAttributedString(string: e.subtitle, attributes: [
                        .foregroundColor: NSColor.secondaryLabelColor,
                        .font: NSFont.systemFont(ofSize: 12),
                    ]))
                }
                item.attributedTitle = title
                target.titles[item] = title
                target.actions.append(action)
                menu.addItem(item)
            }
        }
        // popUp 在菜单关闭前不返回，target 在此期间一直被持有
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + 4), in: view)
        withExtendedLifetime(target) {}
    }

    private func symbol(_ name: String, color: NSColor) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))?
            .withSymbolConfiguration(.init(paletteColors: [color]))
        image?.isTemplate = false
        return image
    }
}

private final class MenuTarget: NSObject, NSMenuDelegate {
    var actions: [() -> Void] = []
    var titles: [NSMenuItem: NSAttributedString] = [:]

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        for entry in menu.items {
            guard let title = titles[entry] else { continue }
            guard entry === item else {
                entry.attributedTitle = title
                continue
            }
            let highlighted = NSMutableAttributedString(attributedString: title)
            let range = NSRange(location: 0, length: highlighted.length)
            highlighted.addAttribute(.foregroundColor, value: NSColor.selectedMenuItemTextColor, range: range)
            title.enumerateAttribute(.attachment, in: range) { value, range, _ in
                guard let original = value as? NSTextAttachment else { return }
                let attachment = NSTextAttachment()
                attachment.bounds = original.bounds
                attachment.image = highlightedImage(original.image)
                highlighted.addAttribute(.attachment, value: attachment, range: range)
            }
            entry.attributedTitle = highlighted
        }
    }

    private func highlightedImage(_ image: NSImage?) -> NSImage? {
        let highlighted = image?.withSymbolConfiguration(.init(paletteColors: [.selectedMenuItemTextColor]))
        highlighted?.isTemplate = false
        return highlighted
    }

    @objc func run(_ sender: NSMenuItem) {
        guard actions.indices.contains(sender.tag) else { return }
        actions[sender.tag]()
    }
}

private final class MenuAnchor {
    weak var view: NSView?
}

/// 取得按钮背后的 NSView，作为菜单的定位基准
private struct AnchorView: NSViewRepresentable {
    let anchor: MenuAnchor

    func makeNSView(context: Context) -> NSView {
        let v = FlippedView()
        anchor.view = v
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        anchor.view = nsView
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
