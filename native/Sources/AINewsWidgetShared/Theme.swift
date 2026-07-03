import SwiftUI

public enum AINewsTheme {
    public static let background = Color(red: 7 / 255, green: 12 / 255, blue: 26 / 255)
    public static let backgroundAlt = Color(red: 12 / 255, green: 21 / 255, blue: 44 / 255)
    public static let panel = Color(red: 16 / 255, green: 24 / 255, blue: 42 / 255)
    public static let panelBorder = Color(red: 59 / 255, green: 97 / 255, blue: 185 / 255)
    public static let textPrimary = Color(red: 231 / 255, green: 239 / 255, blue: 255 / 255)
    public static let textSecondary = Color(red: 154 / 255, green: 171 / 255, blue: 205 / 255)
    public static let textMuted = Color(red: 119 / 255, green: 135 / 255, blue: 171 / 255)
    public static let accentBlue = Color(red: 114 / 255, green: 176 / 255, blue: 255 / 255)
    public static let accentCyan = Color(red: 34 / 255, green: 220 / 255, blue: 183 / 255)
    public static let accentGold = Color(red: 255 / 255, green: 186 / 255, blue: 69 / 255)
    public static let accentRose = Color(red: 255 / 255, green: 110 / 255, blue: 150 / 255)

    public static let cardGradient = LinearGradient(
        colors: [backgroundAlt, panel],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

public extension View {
    func aiNewsPanelStyle() -> some View {
        self
            .background(AINewsTheme.cardGradient)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AINewsTheme.panelBorder.opacity(0.8), lineWidth: 1.2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
