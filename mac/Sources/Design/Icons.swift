import SwiftUI

/// 服务类型图标。键写进配置，改动会影响已存的服务
enum ServiceIcon {
    static let paths: [String: String] = [
        "web": "M3.5 5.5h17v13h-17z M3.5 9.5h17 M6 7.5h.01M8.5 7.5h.01",
        "api": "M12 9.5a2.5 2.5 0 1 0 0 5 2.5 2.5 0 0 0 0-5z M12 3v2.4M12 18.6V21M4.6 7.6l2 1.2M17.4 15.2l2 1.2M4.6 16.4l2-1.2M17.4 8.8l2-1.2",
        "db": "M12 3c4 0 7 1.1 7 2.5S16 8 12 8 5 6.9 5 5.5 8 3 12 3z M5 5.5v13C5 20 8 21 12 21s7-1 7-2.5v-13 M5 12c0 1.4 3 2.5 7 2.5s7-1.1 7-2.5",
        "layers": "M12 3l8 4.4-8 4.4-8-4.4z M4 12l8 4.4 8-4.4 M4 16.4L12 21l8-4.6",
        "queue": "M4 7h10M4 12h10M4 17h6 M15.5 15.6l2.1 2.1 3.9-4.4",
        "doc": "M6.5 3h7l4 4v14h-11z M13.5 3v4h4 M9.5 12h5M9.5 16h5",
        "tunnel": "M10.5 13.5L20 4 M14.5 4H20v5.5 M20 13.5V18a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h4.5",
        "chip": "M8.5 8.5h7v7h-7z M4 10.5h4.5M4 13.5h4.5M15.5 10.5H20M15.5 13.5H20M10.5 4v4.5M13.5 4v4.5M10.5 15.5V20M13.5 15.5V20",
        "pulse": "M3 12h4l2.5-6 3.5 11 2.5-5h5.5",
    ]

    static let tints: [String: Color] = [
        "web": Color(hex: 0x0A7CFF),
        "api": Color(hex: 0xAF52DE),
        "db": Color(hex: 0x30B0C7),
        "layers": Color(hex: 0xFF375F),
        "queue": Color(hex: 0xFF9F0A),
        "doc": Color(hex: 0x8E8E93),
        "tunnel": Color(hex: 0x5E5CE6),
        "chip": Color(hex: 0xFF6B22),
        "pulse": Color(hex: 0x34C759),
    ]

    /// 新建表单里可选的类型
    static let kinds: [(key: String, label: String)] = [
        ("web", "Web / 前端"),
        ("api", "API 服务"),
        ("db", "数据库"),
        ("queue", "Worker"),
        ("chip", "构建任务"),
    ]

    static func path(_ key: String) -> String { paths[key] ?? paths["chip"]! }
    static func tint(_ key: String) -> Color { tints[key] ?? Color(hex: 0x8E8E93) }
}

/// 界面图标
enum UIIcon {
    static let grid = "M4 4h7v7H4zM13 4h7v7h-7zM4 13h7v7H4zM13 13h7v7h-7z"
    static let search = "M11 4.5a6.5 6.5 0 1 0 0 13 6.5 6.5 0 0 0 0-13z M15.8 15.8L20 20"
    static let play = "M12 4.5v6 M17.7 7a7.5 7.5 0 1 1-11.4 0"
    static let stop = "M12 3.2a8.8 8.8 0 1 0 0 17.6 8.8 8.8 0 0 0 0-17.6z M9.6 9.6h4.8v4.8H9.6z"
    static let restart = "M20 12a8 8 0 1 1-2.8-6.1 M20 4v5h-5"
    static let panel = "M4 5h16v14H4z M14 5v14"
    static let bolt = "M13.5 3l-8.5 11h6l-1 7 8.5-11h-6z"
    static let plus = "M12 5.5v13M5.5 12h13"
    static let edit = "M4.5 19.5h4L19 9a2.1 2.1 0 0 0-3-3L5.5 16.5z M14.5 7.5l2 2"
    static let trash = "M5 7.5h14 M9 7.5V5.5h6v2 M6.8 7.5l.8 11.2h8.8l.8-11.2 M10.2 10.5v5M13.8 10.5v5"
    static let cog = "M12 9.5a2.5 2.5 0 1 0 0 5 2.5 2.5 0 0 0 0-5z M12 3v2.4M12 18.6V21M4.6 7.6l2 1.2M17.4 15.2l2 1.2M4.6 16.4l2-1.2M17.4 8.8l2-1.2"
    static let check = "M5 12.6l4.4 4.4L19 7.4"
    static let warn = "M12 4.6l8.4 14.8H3.6z M12 10.2v4M12 16.8h.01"
    static let back = "M14.5 5l-7 7 7 7"
    static let forward = "M9.5 5l7 7-7 7"
    static let clock = "M12 3.5a8.5 8.5 0 1 0 0 17 8.5 8.5 0 0 0 0-17z M12 7.5V12l3 2"
    static let folder = "M3.5 6.5h5.5l2 2.5h9.5v11h-17z"
}
