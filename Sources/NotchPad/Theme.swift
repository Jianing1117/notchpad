import AppKit
import SwiftUI

/// 黑底 + 白字 + 每个 tab 一个荧光色。tab 和分段的颜色可以在配置文件里改。
/// Black panel, white text, one neon accent per tab. Tab and section colors can be set in the config file.
enum Theme {
    static let text = Color.white
    static let dim = Color.white.opacity(0.45)
    static let faint = Color.white.opacity(0.28)
    static let field = Color.white.opacity(0.07)
    static let hover = Color.white.opacity(0.06)
    static let hairline = Color.white.opacity(0.08)

    static let green = Color(hex: "#42FF8C")!
    static let cyan = Color(hex: "#4DD9FF")!
    static let pink = Color(hex: "#FF61B3")!
    static let amber = Color(hex: "#FFCC47")!
    static let violet = Color(hex: "#B399FF")!
    static let gray = Color(hex: "#9E9E9E")!

    /// 配置里没写颜色时，tab 按顺序用这几个 / fallback tab colors, in order
    static let tabAccents = [green, cyan, pink, amber, violet]
    /// 配置里没写颜色时，分段按顺序用这几个 / fallback section colors, in order
    static let sectionColors = [pink, amber, violet, gray]
}

extension Color {
    /// "#42FF8C" or "42FF8C"
    init?(hex: String?) {
        guard var s = hex?.trimmingCharacters(in: .whitespaces) else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
}
