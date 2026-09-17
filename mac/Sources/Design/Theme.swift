import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity)
    }
}

enum Appearance: String, CaseIterable {
    case system, light, dark

    var scheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct Theme {
    var ink: Color
    var ink2: Color
    var ink3: Color
    var blue: Color
    var blueTx: Color
    var blueSoft: Color
    var green: Color
    var greenTx: Color
    var orange: Color
    var orangeTx: Color
    var red: Color
    var redTx: Color
    var sep: Color
    var sep2: Color
    var fill: Color
    var fill2: Color
    /// 窗口本体与分段控件滑块的底色
    var win: Color
    var page: Color
    var card: Color
    var cardStroke: Color
    var cardShadow: Color
    var pop: Color
    var popBorder: Color
    var field: Color
    /// 侧边栏底色。设计稿是半透明叠在不透明窗体上，这里取合成后的实色
    /// 工具条与日志抽屉的底色，同样取合成后的实色
    var chrome: Color
    var teal: Color
    var dim: Color

    static let light = Theme(
        ink: Color(hex: 0x1C1C1E),
        ink2: Color(hex: 0x1C1C1E, opacity: 0.6),
        ink3: Color(hex: 0x1C1C1E, opacity: 0.4),
        blue: Color(hex: 0x0A7CFF),
        blueTx: Color(hex: 0x0563C9),
        blueSoft: Color(hex: 0x0A7CFF, opacity: 0.1),
        green: Color(hex: 0x34C759),
        greenTx: Color(hex: 0x1B7F3E),
        orange: Color(hex: 0xFF9F0A),
        orangeTx: Color(hex: 0x8A5A00),
        red: Color(hex: 0xFF3B30),
        redTx: Color(hex: 0xC4241B),
        sep: Color(hex: 0x3C3C43, opacity: 0.13),
        sep2: Color(hex: 0x3C3C43, opacity: 0.07),
        fill: Color(hex: 0x767680, opacity: 0.08),
        fill2: Color(hex: 0x767680, opacity: 0.14),
        win: .white,
        page: Color(hex: 0xF4F4F7),
        card: .white,
        cardStroke: Color(hex: 0x000000, opacity: 0.055),
        cardShadow: Color(hex: 0x000000, opacity: 0.05),
        pop: Color(hex: 0xFAFAFC, opacity: 0.88),
        popBorder: Color(hex: 0x000000, opacity: 0.1),
        field: .white,
        chrome: Color(hex: 0xFBFBFD),
        teal: Color(hex: 0x30B0C7),
        dim: Color(hex: 0x8E8E93, opacity: 0.55))

    static let dark = Theme(
        ink: Color(hex: 0xF2F2F7),
        ink2: Color(hex: 0xF2F2F7, opacity: 0.64),
        ink3: Color(hex: 0xF2F2F7, opacity: 0.44),
        blue: Color(hex: 0x0A84FF),
        blueTx: Color(hex: 0x7CC0FF),
        blueSoft: Color(hex: 0x0A84FF, opacity: 0.16),
        green: Color(hex: 0x32D74B),
        greenTx: Color(hex: 0x5BE072),
        orange: Color(hex: 0xFF9F0A),
        orangeTx: Color(hex: 0xFFBE5C),
        red: Color(hex: 0xFF453A),
        redTx: Color(hex: 0xFF8078),
        sep: Color(hex: 0xFFFFFF, opacity: 0.12),
        sep2: Color(hex: 0xFFFFFF, opacity: 0.07),
        fill: Color(hex: 0xFFFFFF, opacity: 0.07),
        fill2: Color(hex: 0xFFFFFF, opacity: 0.13),
        win: Color(hex: 0x1C1C1E),
        page: Color(hex: 0x1C1C1E),
        card: Color(hex: 0x2C2C2E),
        cardStroke: Color(hex: 0xFFFFFF, opacity: 0.06),
        cardShadow: .clear,
        pop: Color(hex: 0x2C2C2E, opacity: 0.9),
        popBorder: Color(hex: 0xFFFFFF, opacity: 0.12),
        field: Color(hex: 0x1C1C1E),
        chrome: Color(hex: 0x262628),
        teal: Color(hex: 0x30B0C7),
        dim: Color(hex: 0x8E8E93, opacity: 0.55))

    static func of(_ scheme: ColorScheme) -> Theme {
        scheme == .dark ? .dark : .light
    }

    // MARK: 状态配色

    func dot(_ phase: Phase) -> Color {
        switch phase {
        case .running: green
        case .error: red
        case .stopped: dim
        case .starting, .stopping, .switching: orange
        }
    }

    func text(_ phase: Phase) -> Color {
        switch phase {
        case .running: greenTx
        case .error: redTx
        case .stopped: ink3
        case .starting, .stopping, .switching: orangeTx
        }
    }

    func dot(_ state: RunState) -> Color { dot(Phase(state)) }
    func text(_ state: RunState) -> Color { text(Phase(state)) }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.light
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

/// 按当前配色方案注入主题
struct Themed: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content.environment(\.theme, Theme.of(scheme))
    }
}

extension View {
    func themed() -> some View { modifier(Themed()) }
}
