import SwiftUI

/// 把 SVG 的 `d` 属性解析成 `Path`。
///
/// 支持 M/L/H/V/C/S/Q/T/A/Z 及各自的相对写法。图标都画在 24 单位的方形视窗里，
/// 解析结果按目标矩形等比缩放。
enum SVGPath {
    /// 同一条路径会被反复绘制，解析结果按视窗坐标缓存，绘制时只做一次仿射变换。
    /// 只在主线程的渲染流程里读写
    nonisolated(unsafe) private static var cache: [String: Path] = [:]

    static func parse(_ d: String, into rect: CGRect, viewBox: CGFloat) -> Path {
        let key = "\(viewBox)|\(d)"
        let unit = cache[key] ?? {
            let p = build(d, viewBox: viewBox)
            cache[key] = p
            return p
        }()
        let s = min(rect.width, rect.height) / viewBox
        return unit.applying(
            CGAffineTransform(scaleX: s, y: s).concatenating(
                CGAffineTransform(
                    translationX: rect.minX + (rect.width - viewBox * s) / 2,
                    y: rect.minY + (rect.height - viewBox * s) / 2)))
    }

    /// 在 viewBox 的原始坐标系里解析
    private static func build(_ d: String, viewBox: CGFloat) -> Path {
        var scanner = Scanner(d)
        var path = Path()

        // 当前点、子路径起点，以及上一段控制点（S/T 需要据此反射）
        var cur = CGPoint.zero
        var start = CGPoint.zero
        var lastCubic: CGPoint?
        var lastQuad: CGPoint?
        var cmd: Character = "M"

        while let next = scanner.command(after: cmd) {
            cmd = next
            let rel = cmd.isLowercase
            let upper = Character(cmd.uppercased())

            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                rel ? CGPoint(x: cur.x + x, y: cur.y + y) : CGPoint(x: x, y: y)
            }

            switch upper {
            case "M":
                guard let x = scanner.number(), let y = scanner.number() else { break }
                cur = point(x, y)
                start = cur
                path.move(to: cur)
                lastCubic = nil
                lastQuad = nil
                // 同一段里后续的坐标对按 L 处理
                while scanner.hasNumber {
                    guard let x = scanner.number(), let y = scanner.number() else { break }
                    cur = point(x, y)
                    path.addLine(to: cur)
                }
            case "L":
                while scanner.hasNumber {
                    guard let x = scanner.number(), let y = scanner.number() else { break }
                    cur = point(x, y)
                    path.addLine(to: cur)
                }
                lastCubic = nil
                lastQuad = nil
            case "H":
                while let x = scanner.number() {
                    cur = CGPoint(x: rel ? cur.x + x : x, y: cur.y)
                    path.addLine(to: cur)
                }
                lastCubic = nil
                lastQuad = nil
            case "V":
                while let y = scanner.number() {
                    cur = CGPoint(x: cur.x, y: rel ? cur.y + y : y)
                    path.addLine(to: cur)
                }
                lastCubic = nil
                lastQuad = nil
            case "C":
                while scanner.hasNumber {
                    guard let a = scanner.pair(), let b = scanner.pair(), let e = scanner.pair() else { break }
                    let c1 = point(a.x, a.y), c2 = point(b.x, b.y), end = point(e.x, e.y)
                    path.addCurve(to: end, control1: c1, control2: c2)
                    cur = end
                    lastCubic = c2
                    lastQuad = nil
                }
            case "S":
                while scanner.hasNumber {
                    guard let b = scanner.pair(), let e = scanner.pair() else { break }
                    let c1 = reflect(lastCubic, about: cur)
                    let c2 = point(b.x, b.y), end = point(e.x, e.y)
                    path.addCurve(to: end, control1: c1, control2: c2)
                    cur = end
                    lastCubic = c2
                    lastQuad = nil
                }
            case "Q":
                while scanner.hasNumber {
                    guard let a = scanner.pair(), let e = scanner.pair() else { break }
                    let c = point(a.x, a.y), end = point(e.x, e.y)
                    path.addQuadCurve(to: end, control: c)
                    cur = end
                    lastQuad = c
                    lastCubic = nil
                }
            case "T":
                while scanner.hasNumber {
                    guard let e = scanner.pair() else { break }
                    let c = reflect(lastQuad, about: cur)
                    let end = point(e.x, e.y)
                    path.addQuadCurve(to: end, control: c)
                    cur = end
                    lastQuad = c
                    lastCubic = nil
                }
            case "A":
                while scanner.hasNumber {
                    guard let rx = scanner.number(), let ry = scanner.number(),
                          let rot = scanner.number(), let large = scanner.flag(),
                          let sweep = scanner.flag(), let e = scanner.pair()
                    else { break }
                    let end = point(e.x, e.y)
                    for seg in arcSegments(
                        from: cur, to: end, rx: rx, ry: ry,
                        rotation: rot, largeArc: large, sweep: sweep)
                    {
                        path.addCurve(to: seg.end, control1: seg.c1, control2: seg.c2)
                    }
                    cur = end
                    lastCubic = nil
                    lastQuad = nil
                }
            case "Z":
                path.closeSubpath()
                cur = start
                lastCubic = nil
                lastQuad = nil
            default:
                break
            }
        }
        return path
    }

    private static func reflect(_ control: CGPoint?, about p: CGPoint) -> CGPoint {
        guard let control else { return p }
        return CGPoint(x: 2 * p.x - control.x, y: 2 * p.y - control.y)
    }

    // MARK: 圆弧转三次贝塞尔

    private struct Segment {
        var c1: CGPoint
        var c2: CGPoint
        var end: CGPoint
    }

    /// 按 SVG 规范 F.6 的端点参数化转中心参数化，再按每段不超过 90° 切成贝塞尔
    private static func arcSegments(
        from p0: CGPoint, to p1: CGPoint,
        rx: CGFloat, ry: CGFloat, rotation: CGFloat,
        largeArc: Bool, sweep: Bool
    ) -> [Segment] {
        var rx = abs(rx), ry = abs(ry)
        if rx == 0 || ry == 0 || (p0.x == p1.x && p0.y == p1.y) {
            return [Segment(c1: p0, c2: p1, end: p1)]
        }
        let phi = rotation * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)

        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1 = cosPhi * dx + sinPhi * dy
        let y1 = -sinPhi * dx + cosPhi * dy

        // 半径不足以连接两个端点时按规范等比放大
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 {
            let k = sqrt(lambda)
            rx *= k
            ry *= k
        }

        let sign: CGFloat = largeArc == sweep ? -1 : 1
        let num = max(0, rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1)
        let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
        let coef = sign * sqrt(den == 0 ? 0 : num / den)
        let cx1 = coef * rx * y1 / ry
        let cy1 = -coef * ry * x1 / rx

        let cx = cosPhi * cx1 - sinPhi * cy1 + (p0.x + p1.x) / 2
        let cy = sinPhi * cx1 + cosPhi * cy1 + (p0.y + p1.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let len = sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy)
            let a = acos(min(1, max(-1, len == 0 ? 1 : dot / len)))
            return (ux * vy - uy * vx < 0) ? -a : a
        }

        let ux = (x1 - cx1) / rx, uy = (y1 - cy1) / ry
        let vx = (-x1 - cx1) / rx, vy = (-y1 - cy1) / ry
        let theta = angle(1, 0, ux, uy)
        var delta = angle(ux, uy, vx, vy)
        if !sweep, delta > 0 { delta -= 2 * .pi }
        if sweep, delta < 0 { delta += 2 * .pi }

        let count = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / CGFloat(count)
        let k = 4.0 / 3.0 * tan(step / 4)

        func onArc(_ t: CGFloat) -> CGPoint {
            let x = rx * cos(t), y = ry * sin(t)
            return CGPoint(x: cosPhi * x - sinPhi * y + cx, y: sinPhi * x + cosPhi * y + cy)
        }
        func slope(_ t: CGFloat) -> CGPoint {
            let x = -rx * sin(t), y = ry * cos(t)
            return CGPoint(x: cosPhi * x - sinPhi * y, y: sinPhi * x + cosPhi * y)
        }

        var out: [Segment] = []
        for i in 0..<count {
            let t0 = theta + CGFloat(i) * step
            let t1 = t0 + step
            let a = onArc(t0), b = onArc(t1)
            let da = slope(t0), db = slope(t1)
            out.append(Segment(
                c1: CGPoint(x: a.x + k * da.x, y: a.y + k * da.y),
                c2: CGPoint(x: b.x - k * db.x, y: b.y - k * db.y),
                end: b))
        }
        return out
    }

    // MARK: 词法扫描

    /// 逐字符扫描路径串。数字可以紧挨着写（`.5.5`、`1-2`），因此不能按空白切词
    private struct Scanner {
        private let chars: [Character]
        private var i = 0

        init(_ s: String) { chars = Array(s) }

        private mutating func skipSeparators() {
            while i < chars.count, chars[i] == " " || chars[i] == "," || chars[i] == "\n" || chars[i] == "\t" {
                i += 1
            }
        }

        var hasNumber: Bool {
            var j = i
            while j < chars.count, chars[j] == " " || chars[j] == "," || chars[j] == "\n" || chars[j] == "\t" {
                j += 1
            }
            guard j < chars.count else { return false }
            return chars[j].isNumber || chars[j] == "-" || chars[j] == "+" || chars[j] == "."
        }

        /// 取下一个命令字母；若紧接着的是数字则重复上一条命令（M 之后重复为 L）
        mutating func command(after previous: Character) -> Character? {
            skipSeparators()
            guard i < chars.count else { return nil }
            if chars[i].isLetter {
                let c = chars[i]
                i += 1
                return c
            }
            switch previous {
            case "M": return "L"
            case "m": return "l"
            default: return previous
            }
        }

        mutating func number() -> CGFloat? {
            skipSeparators()
            guard i < chars.count else { return nil }
            var s = ""
            if chars[i] == "-" || chars[i] == "+" {
                s.append(chars[i])
                i += 1
            }
            var sawDot = false
            while i < chars.count {
                let c = chars[i]
                if c.isNumber {
                    s.append(c)
                } else if c == "." && !sawDot {
                    sawDot = true
                    s.append(c)
                } else if (c == "e" || c == "E"), i + 1 < chars.count,
                          chars[i + 1].isNumber || chars[i + 1] == "-" || chars[i + 1] == "+" {
                    s.append(c)
                    i += 1
                    s.append(chars[i])
                } else {
                    break
                }
                i += 1
            }
            return Double(s).map { CGFloat($0) }
        }

        mutating func pair() -> CGPoint? {
            guard let x = number(), let y = number() else { return nil }
            return CGPoint(x: x, y: y)
        }

        /// 圆弧的两个标志位是单个字符，可以不带分隔符紧挨着写
        mutating func flag() -> Bool? {
            skipSeparators()
            guard i < chars.count else { return nil }
            let c = chars[i]
            guard c == "0" || c == "1" else { return number().map { $0 != 0 } }
            i += 1
            return c == "1"
        }
    }
}

/// 以 SVG 路径绘制的图标。线宽按视窗单位给出，随尺寸一起缩放。
///
/// 做成 `Shape` 而不是包一层 `GeometryReader`：图标数量多，多一层 GeometryReader
/// 就多一层参与布局的容器，监控面板一屏有几十个，布局开销很可观
struct Glyph: Shape {
    let path: String
    var lineWidth: CGFloat = 1.8
    var viewBox: CGFloat = 24

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        return SVGPath.parse(path, into: rect, viewBox: viewBox)
            .strokedPath(
                StrokeStyle(
                    lineWidth: lineWidth * side / viewBox, lineCap: .round, lineJoin: .round))
    }
}
