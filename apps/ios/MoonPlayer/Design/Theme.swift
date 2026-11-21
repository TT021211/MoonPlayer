import SwiftUI

enum Theme {
    static let background = Color(red: 0.045, green: 0.045, blue: 0.058)
    static let surface = Color(red: 0.086, green: 0.086, blue: 0.106)
    static let surfaceHigh = Color(red: 0.13, green: 0.13, blue: 0.16)
    static let accent = Color(red: 1.00, green: 0.31, blue: 0.24)
    static let accentSoft = Color(red: 1.00, green: 0.31, blue: 0.24).opacity(0.18)
    static let textSecondary = Color.white.opacity(0.62)
    static let textTertiary = Color.white.opacity(0.42)
    static let stroke = Color.white.opacity(0.08)

    static let cardRadius: CGFloat = 12
    static let posterRadius: CGFloat = 10
}
