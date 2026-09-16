import AppKit
import SwiftUI

/// 按 CSS flex 的规则横向分配宽度：子项先各拿基准宽度，剩余空间在可伸缩的子项间等分。
/// SwiftUI 的 HStack 只等分总宽，基准不同的列会被拉成一样宽
struct FlexRow: Layout {
    /// 每个子项的基准宽度，以及是否参与伸缩
    let items: [(basis: CGFloat, grows: Bool)]

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let available = proposal.width ?? basisTotal
        let height =
            zip(subviews, widths(in: available))
            .map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }
            .max() ?? 0
        return CGSize(width: available, height: height)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        var x = bounds.minX
        for (sub, w) in zip(subviews, widths(in: bounds.width)) {
            sub.place(
                at: CGPoint(x: x, y: bounds.minY),
                proposal: ProposedViewSize(width: w, height: bounds.height))
            x += w
        }
    }

    private var basisTotal: CGFloat { items.reduce(0) { $0 + $1.basis } }

    private func widths(in available: CGFloat) -> [CGFloat] {
        let growers = items.filter(\.grows).count
        let extra = growers == 0 ? 0 : max(0, available - basisTotal) / CGFloat(growers)
        return items.map { $0.basis + ($0.grows ? extra : 0) }
    }
}

/// 设计稿的行高统一是字号的 1.45 倍，SwiftUI 单行文本默认只有约 1.19 倍。
/// 单行文本显式撑到设计稿的行盒高度，竖向节奏才对得上
extension View {
    func lineBox(_ size: CGFloat) -> some View {
        frame(height: (size * 1.45).rounded())
    }
}

// MARK: 状态圆点

/// 状态圆点。运行中与异常带呼吸光晕，启动中与停止中闪烁，其余静止
struct Dot: View {
    let phase: Phase
    var size: CGFloat = 7
    @Environment(\.theme) private var theme

    init(phase: Phase, size: CGFloat = 7) {
        self.phase = phase
        self.size = size
    }

    init(state: RunState, size: CGFloat = 7) {
        self.init(phase: Phase(state), size: size)
    }

    private var breathes: Bool { phase == .running || phase == .error }
    /// 异常时呼吸更急促
    private var period: Double { phase == .error ? 1.7 : 2.8 }

    var body: some View {
        if phase.busy {
            Blink(color: theme.dot(phase))
                .frame(width: size, height: size)
                .allowsHitTesting(false)
        } else {
            Circle()
                .fill(theme.dot(phase))
                .frame(width: size, height: size)
                .overlay {
                    if breathes {
                        Halo(color: theme.dot(phase), period: period)
                            .frame(width: size * 2.6, height: size * 2.6)
                            .allowsHitTesting(false)
                    }
                }
        }
    }
}

/// 过渡中的圆点，明暗与大小一起起伏。与呼吸光晕一样交给 Core Animation
private struct Blink: NSViewRepresentable {
    let color: Color

    func makeNSView(context: Context) -> BlinkView { BlinkView(frame: .zero) }

    func updateNSView(_ v: BlinkView, context: Context) {
        v.configure(NSColor(color).cgColor)
    }
}

private final class BlinkView: NSView {
    private let dot = CAShapeLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(dot)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ color: CGColor) {
        guard dot.fillColor != color else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dot.fillColor = color
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        guard bounds.width > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dot.frame = bounds
        dot.path = CGPath(ellipseIn: bounds, transform: nil)
        CATransaction.commit()
        if dot.animation(forKey: "blink") == nil { install() }
    }

    /// 设计稿 blinkDot：0.85 秒一个来回，半程时透明度 0.34、缩到 0.78
    private func install() {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1.0
        fade.toValue = 0.34
        let shrink = CABasicAnimation(keyPath: "transform.scale")
        shrink.fromValue = 1.0
        shrink.toValue = 0.78
        let group = CAAnimationGroup()
        group.animations = [fade, shrink]
        group.duration = 0.425
        group.autoreverses = true
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dot.add(group, forKey: "blink")
    }
}

/// 呼吸光晕。
///
/// 交给 Core Animation 而不是 SwiftUI 的 `repeatForever`：后者会让整棵视图树按屏幕刷新率
/// 重绘，实测监控面板上一个圆点就占掉约 14% 的单核；CA 动画跑在渲染服务里，进程每帧无开销
private struct Halo: NSViewRepresentable {
    let color: Color
    let period: Double

    func makeNSView(context: Context) -> HaloView {
        let v = HaloView()
        v.configure(color: NSColor(color), period: period)
        return v
    }

    func updateNSView(_ v: HaloView, context: Context) {
        v.configure(color: NSColor(color), period: period)
    }
}

/// 尺寸要等 SwiftUI 布局完成才知道，因此在视图自己的 `layout()` 里设置路径并装动画
private final class HaloView: NSView {
    private let ring = CAShapeLayer()
    private var period: Double = 2.8

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        ring.fillColor = nil
        ring.lineWidth = 2
        ring.opacity = 0
        layer?.addSublayer(ring)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// SwiftUI 每次重建父视图都会调到这里；无条件置 `needsLayout` 会让 AppKit 每帧重排，
    /// 因此只在颜色或节奏真的变了才动
    func configure(color: NSColor, period: Double) {
        let cg = color.cgColor
        if ring.strokeColor != cg { ring.strokeColor = cg }
        guard self.period != period else { return }
        self.period = period
        ring.removeAnimation(forKey: "pulse")
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard bounds.width > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.frame = bounds
        // 起始半径就是圆点本身，向外扩散
        let inset = bounds.width * 0.31
        ring.path = CGPath(ellipseIn: bounds.insetBy(dx: inset, dy: inset), transform: nil)
        CATransaction.commit()
        if ring.animation(forKey: "pulse") == nil { install() }
    }

    private func install() {
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.0
        scale.toValue = 2.1
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.55
        fade.toValue = 0.0

        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = period
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ring.add(group, forKey: "pulse")
    }
}

// MARK: 卡片

struct Card<Content: View>: View {
    var radius: CGFloat = 11
    @ViewBuilder var content: Content
    @Environment(\.theme) private var theme

    var body: some View {
        content
            .background(theme.card)
            .clipShape(.rect(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(theme.cardStroke, lineWidth: 0.5)
            }
            .shadow(color: theme.cardShadow, radius: 1.25, y: 1)
    }
}

// MARK: 分段控件

struct Segmented<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    var font: Font = .system(size: 12)
    @Environment(\.theme) private var theme
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { opt in
                let on = opt.value == selection
                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        selection = opt.value
                    }
                } label: {
                    Text(opt.label)
                        .font(font)
                        .fontWeight(on ? .medium : .regular)
                        .foregroundStyle(on ? theme.ink : theme.ink2)
                        .lineBox(12)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .contentShape(.rect)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 5.5)
                                    .fill(theme.win)
                                    .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
                                    .matchedGeometryEffect(id: "thumb", in: thumb)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(theme.fill, in: .rect(cornerRadius: 7))
    }
}

// MARK: 开关

struct Switch: View {
    @Binding var isOn: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.8)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? theme.blue : theme.fill2)
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1)
                    .padding(2)
            }
            .frame(width: 40, height: 24)
            .contentShape(.rect)
        }
        .buttonStyle(Press())
    }
}

// MARK: 曲线

/// 折线加填充面积。`max` 为满刻度，传 nil 时按序列自身峰值归一；
/// `floor` 是归一时的刻度下限，用来压住低占用序列被放大成剧烈起伏
struct Spark: View {
    let values: [Double]
    var max: Double?
    var floor: Double = 0
    var line: Color
    var fill: Color
    var lineWidth: CGFloat = 1.6
    /// 顶部留白比例，避免峰值贴边
    private let headroom = 0.9

    var body: some View {
        let peak = Swift.max(max ?? Swift.max(values.max() ?? 1, floor), 0.0001)
        ZStack {
            SparkShape(values: values, peak: peak, headroom: headroom, closed: true).fill(fill)
            SparkShape(values: values, peak: peak, headroom: headroom, closed: false)
                .stroke(
                    line,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct SparkShape: Shape {
    let values: [Double]
    let peak: Double
    let headroom: Double
    /// 闭合成面积，用于填充
    let closed: Bool

    func path(in rect: CGRect) -> Path {
        guard values.count > 1 else { return Path() }
        let step = rect.width / CGFloat(values.count - 1)
        let pts = values.enumerated().map { i, v -> CGPoint in
            let clamped = Swift.min(Swift.max(v, 0), peak)
            return CGPoint(
                x: rect.minX + CGFloat(i) * step,
                y: rect.maxY - CGFloat(clamped / peak) * rect.height * headroom)
        }
        var p = Path()
        p.move(to: pts[0])
        for pt in pts.dropFirst() { p.addLine(to: pt) }
        if closed {
            p.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: rect.maxY))
            p.addLine(to: CGPoint(x: pts[0].x, y: rect.maxY))
            p.closeSubpath()
        }
        return p
    }
}

// MARK: 进度条

struct Bar: View {
    /// 0…1
    let value: Double
    var color: Color
    var height: CGFloat = 4
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(theme.fill2)
            BarFill(value: value).fill(color)
        }
        .frame(height: height)
    }
}

private struct BarFill: Shape {
    let value: Double

    func path(in rect: CGRect) -> Path {
        let w = rect.width * Swift.min(Swift.max(value, 0), 1)
        guard w > 0 else { return Path() }
        return Capsule().path(in: CGRect(x: rect.minX, y: rect.minY, width: w, height: rect.height))
    }
}

// MARK: 图标徽章

struct IconBadge: View {
    let ic: String
    var side: CGFloat = 28
    var glyph: CGFloat = 16
    /// 设计稿：运行中不透明，过渡中 0.72，其余 0.45
    var phase: Phase = .running

    var body: some View {
        RoundedRectangle(cornerRadius: side * 0.27)
            .fill(ServiceIcon.tint(ic))
            .frame(width: side, height: side)
            .overlay {
                Glyph(path: ServiceIcon.path(ic))
                    .foregroundStyle(.white)
                    .frame(width: glyph, height: glyph)
            }
            .opacity(phase == .running ? 1 : (phase.busy ? 0.72 : 0.45))
    }
}

// MARK: 进场动效

extension AnyTransition {
    /// 设计稿 viewIn：自下方 7pt 处淡入
    static var viewIn: AnyTransition { .opacity.combined(with: .offset(y: 7)) }
}

// MARK: 按钮

/// 按下时缩一下。`.plain` 样式本身不给任何提示；缩放比例与曲线取自设计稿
struct Press: ButtonStyle {
    var scale: CGFloat = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(
                .timingCurve(0.32, 0.72, 0, 1, duration: 0.14), value: configuration.isPressed)
    }
}

/// 工具栏上的小方按钮
struct ChromeButton: View {
    let path: String
    var help: String = ""
    var tint: Color?
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            ChromeFace(
                path: path, idle: theme.ink2, hot: tint ?? theme.ink,
                base: theme.fill, hover: theme.fill2
            )
            .frame(width: 28, height: 26)
            .contentShape(.rect)
        }
        .buttonStyle(Press())
        .help(help)
    }
}

/// 工具栏按钮的底色与图标。
///
/// 整个按钮面由图层绘制，悬浮时底色与图标颜色一起变——用 `onHover` 做同样的事会让
/// 整个窗口每收到一个指针事件就遍历一遍响应者树，见 `HoverHighlight`
private struct ChromeFace: NSViewRepresentable {
    let path: String
    let idle: Color
    let hot: Color
    let base: Color
    let hover: Color

    func makeNSView(context: Context) -> ChromeFaceView { ChromeFaceView(frame: .zero) }

    func updateNSView(_ v: ChromeFaceView, context: Context) {
        v.configure(
            path: path, idle: NSColor(idle).cgColor, hot: NSColor(hot).cgColor,
            base: NSColor(base).cgColor, hover: NSColor(hover).cgColor)
    }
}

final class ChromeFaceView: NSView {
    /// 图标边长与描边宽度，与设计稿一致
    private static let side: CGFloat = 15
    private static let stroke: CGFloat = 2

    private let glyph = CAShapeLayer()
    private var d = ""
    private var idle: CGColor?
    private var hot: CGColor?
    private var base: CGColor?
    private var hover: CGColor?
    private var inside = false

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        // 不裁剪时 visibleRect 会超出自身，跟踪区域随之变大，见 HoverSensor
        clipsToBounds = true
        layer?.cornerRadius = 7
        glyph.fillColor = nil
        glyph.lineCap = .round
        glyph.lineJoin = .round
        glyph.lineWidth = Self.stroke * Self.side / 24
        layer?.addSublayer(glyph)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(path: String, idle: CGColor, hot: CGColor, base: CGColor, hover: CGColor) {
        self.idle = idle
        self.hot = hot
        self.base = base
        self.hover = hover
        if d != path {
            d = path
            needsLayout = true
        }
        paint()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        inside = true
        NSCursor.pointingHand.set()
        paint()
    }

    override func mouseExited(with event: NSEvent) {
        inside = false
        NSCursor.arrow.set()
        paint()
    }

    override func layout() {
        super.layout()
        glyph.frame = bounds
        let box = CGRect(
            x: (bounds.width - Self.side) / 2, y: (bounds.height - Self.side) / 2,
            width: Self.side, height: Self.side)
        // SVG 的 y 轴向下，图层坐标向上
        var flip = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -bounds.height)
        glyph.path = SVGPath.parse(d, into: box, viewBox: 24).cgPath.copy(using: &flip)
    }

    private func paint() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.backgroundColor = inside ? hover : base
        glyph.strokeColor = inside ? hot : idle
        CATransaction.commit()
    }
}

/// 启动 / 停止的圆角方钮。停止态用蓝色实心，运行态用灰底
struct RunButton: View {
    let phase: Phase
    var side: CGFloat = 28
    var height: CGFloat = 26
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            SpinGlyph(
                path: phase.runIcon, color: phase.quiet ? theme.ink : .white,
                spinning: phase.busy
            )
            .frame(width: 15, height: 15)
            .frame(width: side, height: height)
            .background(phase.quiet ? theme.fill2 : theme.blue, in: .rect(cornerRadius: 7))
        }
        .buttonStyle(Press(scale: 0.92))
        .help(phase.runLabel)
    }
}

extension Phase {
    /// 运行中与过渡中的启停按钮用灰底，其余用蓝底
    var quiet: Bool { self == .running || busy }
    var runIcon: String { busy ? UIIcon.restart : (self == .running ? UIIcon.stop : UIIcon.play) }
    var runLabel: String { busy ? label : (self == .running ? "停止" : "启动") }
}

/// 可旋转的线条图标。过渡中的启停按钮用它转圈，旋转交给 Core Animation
struct SpinGlyph: NSViewRepresentable {
    let path: String
    let color: Color
    var lineWidth: CGFloat = 1.9
    let spinning: Bool

    func makeNSView(context: Context) -> SpinView { SpinView(frame: .zero) }

    func updateNSView(_ v: SpinView, context: Context) {
        v.configure(
            path: path, color: NSColor(color).cgColor, lineWidth: lineWidth, spinning: spinning)
    }
}

final class SpinView: NSView {
    private let shape = CAShapeLayer()
    private var d = ""
    private var width: CGFloat = 1.9

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        shape.fillColor = nil
        shape.lineCap = .round
        shape.lineJoin = .round
        layer?.addSublayer(shape)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(path: String, color: CGColor, lineWidth: CGFloat, spinning: Bool) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.18)
        shape.strokeColor = color
        CATransaction.commit()
        if d != path || width != lineWidth {
            d = path
            width = lineWidth
            needsLayout = true
        }
        if !spinning {
            shape.removeAnimation(forKey: "spin")
        } else if shape.animation(forKey: "spin") == nil {
            // 设计稿 spin .9s linear，顺时针
            let turn = CABasicAnimation(keyPath: "transform.rotation.z")
            turn.fromValue = 0
            turn.toValue = -2 * CGFloat.pi
            turn.duration = 0.9
            turn.repeatCount = .infinity
            shape.add(turn, forKey: "spin")
        }
    }

    override func layout() {
        super.layout()
        guard bounds.width > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.frame = bounds
        shape.lineWidth = width * bounds.width / 24
        // SVG 的 y 轴向下，图层坐标向上
        var flip = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -bounds.height)
        shape.path = SVGPath.parse(d, into: bounds, viewBox: 24).cgPath.copy(using: &flip)
        CATransaction.commit()
    }
}

// MARK: 输入框

/// 带放大镜图标的单行搜索框
struct SearchBox: View {
    let placeholder: String
    @Binding var text: String
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 7) {
            Glyph(path: UIIcon.search, lineWidth: 1.9)
                .foregroundStyle(theme.ink3)
                .frame(width: 13, height: 13)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(theme.ink)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(theme.win, in: .rect(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7).strokeBorder(theme.sep, lineWidth: 0.5)
        }
    }
}

struct Field: View {
    let placeholder: String
    @Binding var text: String
    var mono = false
    @Environment(\.theme) private var theme
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(mono ? .system(size: 12.5, design: .monospaced) : .system(size: 13))
            .foregroundStyle(theme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(theme.field, in: .rect(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(focused ? theme.blue.opacity(0.7) : theme.sep, lineWidth: focused ? 1.5 : 0.5)
            }
            .focused($focused)
    }
}

// MARK: 材质背景

// MARK: 悬停高亮

/// 悬停底色。列表行、工具栏按钮都用它。
///
/// 底色由 AppKit 跟踪区域直接改图层，不用 `onHover`：视图树里只要还有一处 `onHover`，
/// SwiftUI 就会为每个指针事件从根节点遍历整棵响应者树做命中测试，实测约 0.9 毫秒一次；
/// 一处都没有时这条派发路径不再进入
struct HoverHighlight: ViewModifier {
    var radius: CGFloat = 0
    /// 未悬浮时的底色
    var base: Color = .clear
    var tint: Color?
    /// 指针停在上面时的形态，传 nil 保持系统默认
    var cursor: NSCursor? = .pointingHand
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content.background(
            HoverLayer(radius: radius, base: base, hover: tint ?? theme.fill, cursor: cursor))
    }
}

extension View {
    func hoverHighlight(
        radius: CGFloat = 0, base: Color = .clear, tint: Color? = nil,
        cursor: NSCursor? = .pointingHand
    ) -> some View {
        modifier(HoverHighlight(radius: radius, base: base, tint: tint, cursor: cursor))
    }
}

private struct HoverLayer: NSViewRepresentable {
    let radius: CGFloat
    let base: Color
    let hover: Color
    let cursor: NSCursor?

    func makeNSView(context: Context) -> HoverView { HoverView(frame: .zero) }

    func updateNSView(_ v: HoverView, context: Context) {
        v.configure(
            radius: radius, base: NSColor(base).cgColor, hover: NSColor(hover).cgColor,
            cursor: cursor)
    }
}

/// 只由跟踪区域驱动底色，自身不接受点击
final class HoverView: NSView {
    private let plate = CALayer()
    private let sensor = HoverSensor()
    private var base: CGColor?
    private var tint: CGColor?
    private var cursor: NSCursor?
    private var inside = false

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(plate)
        addSubview(sensor)
        sensor.onChange = { [weak self] in self?.set($0) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(radius: CGFloat, base: CGColor, hover: CGColor, cursor: NSCursor?) {
        self.base = base
        tint = hover
        self.cursor = cursor
        plate.cornerRadius = radius
        paint(animated: false)
    }

    override func layout() {
        super.layout()
        sensor.frame = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        plate.frame = bounds
        CATransaction.commit()
    }

    private func set(_ now: Bool) {
        guard now != inside else { return }
        inside = now
        if let cursor { (now ? cursor : NSCursor.arrow).set() }
        paint(animated: true)
    }

    private func paint(animated: Bool) {
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(0.16)
        } else {
            CATransaction.setDisableActions(true)
        }
        plate.backgroundColor = inside ? tint : base
        CATransaction.commit()
    }
}

/// 与所在视图同大的感应区，报告指针进出。应用不在前台时也跟随指针，与系统侧边栏一致
private final class HoverSensor: NSView {
    var onChange: ((Bool) -> Void)?
    private var scrollWatch: NSObjectProtocol?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        // macOS 14 起不裁剪的视图 visibleRect 不再受自身边界限制，会等于整片滚动可视区，
        // 跟踪区域随之覆盖整个列表
        clipsToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self))
        recheck()
    }

    /// 内容在静止的指针下方滚动时，系统不会补发进出事件
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let scrollWatch { NotificationCenter.default.removeObserver(scrollWatch) }
        scrollWatch = nil
        guard let scroll = enclosingScrollView else { return }
        scroll.contentView.postsBoundsChangedNotifications = true
        scrollWatch = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.recheck() }
        }
    }

    override func mouseEntered(with event: NSEvent) { onChange?(true) }
    override func mouseExited(with event: NSEvent) { onChange?(false) }

    private func recheck() {
        guard let window else { return }
        let p = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        onChange?(bounds.intersection(visibleRect).contains(p))
    }
}

/// 分区小标题
struct SectionLabel: View {
    let text: String
    @Environment(\.theme) private var theme

    var body: some View {
        Text(text)
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(theme.ink2)
    }
}
