import Foundation

enum Fmt {
    /// 运行时长
    static func uptime(_ seconds: Double) -> String {
        guard seconds > 0 else { return "—" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        return h > 0 ? "\(h) 小时 \(m) 分" : "\(m) 分 \(total % 60) 秒"
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
