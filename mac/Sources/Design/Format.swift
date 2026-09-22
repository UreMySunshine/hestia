import Foundation

enum Fmt {
    /// 运行时长，如 45s、12m 5s、5h 12m、1d 4h；未运行时为「—」
    static func uptime(_ seconds: Double) -> String {
        seconds > 0 ? duration(seconds) : "—"
    }

    /// 紧凑时长的各段，取最大的两级单位，第二级为 0 时省略：45s、12m 5s、5h 12m、1d 4h、3d。
    /// `seconds` 为假时只到分钟，不足 1 分钟记为 <1m，供按分钟刷新的地方使用
    static func span(_ t: Double, seconds: Bool = true) -> [(value: String, unit: String)] {
        let total = max(0, Int(t))
        let d = total / 86400, h = total % 86400 / 3600, m = total % 3600 / 60, s = total % 60
        func two(_ a: Int, _ ua: String, _ b: Int, _ ub: String) -> [(value: String, unit: String)] {
            b > 0 ? [("\(a)", ua), ("\(b)", ub)] : [("\(a)", ua)]
        }
        if d > 0 { return two(d, "d", h, "h") }
        if h > 0 { return two(h, "h", m, "m") }
        if !seconds { return [(m < 1 ? "<1" : "\(m)", "m")] }
        if m > 0 { return two(m, "m", s, "s") }
        return [("\(s)", "s")]
    }

    /// 时长，如 38s、1m 4s、5h 12m
    static func duration(_ seconds: Double) -> String {
        span(seconds).map { $0.value + $0.unit }.joined(separator: " ")
    }

    static func cpu(_ v: Double) -> String { String(format: "%.1f", v) }

    /// 千分位，如 4,000
    static func grouped(_ n: Int) -> String { n.formatted(.number.grouping(.automatic)) }

    static func mem(_ mb: Double) -> String {
        mb >= 1024 ? String(format: "%.1f GB", mb / 1024) : "\(Int(mb.rounded())) MB"
    }

    static func clock(_ ms: UInt64) -> String {
        let d = Date(timeIntervalSince1970: Double(ms) / 1000)
        return clockFormatter.string(from: d)
    }

    static func hourMinute(_ d: Date) -> String { hourMinuteFormatter.string(from: d) }

    private static let hourMinuteFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    static func port(_ p: UInt16) -> String { p == 0 ? "—" : String(p) }
}

enum Machine {
    /// 物理内存，单位 MB
    static let memoryMB = Double(ProcessInfo.processInfo.physicalMemory) / 1_048_576

    static let memoryGB = Int((memoryMB / 1024).rounded())
}
