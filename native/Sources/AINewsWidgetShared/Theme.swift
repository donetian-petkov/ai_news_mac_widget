import SwiftUI
import Combine
#if canImport(AppKit)
import AppKit
#endif

private func hex(_ value: UInt32, _ alpha: Double = 1) -> Color {
    Color(
        red: Double((value >> 16) & 0xFF) / 255,
        green: Double((value >> 8) & 0xFF) / 255,
        blue: Double(value & 0xFF) / 255,
        opacity: alpha
    )
}

/// A full color palette for one theme ("vibe").
public struct ThemePalette: Sendable {
    public var background: Color
    public var backgroundAlt: Color
    public var panel: Color
    public var panelBorder: Color
    public var textPrimary: Color
    public var textSecondary: Color
    public var textMuted: Color
    public var accentBlue: Color
    public var accentCyan: Color
    public var accentGold: Color
    public var accentRose: Color
}

/// The selectable themes, ported from the original web app's "vibe" palettes.
public enum AINewsVibe: String, CaseIterable, Sendable {
    case dark, light, newspaper, cinema, scifi, cyberwitch, fantasy, anime, arcade

    public var displayName: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        case .newspaper: return "Newspaper"
        case .cinema: return "Cinema"
        case .scifi: return "Sci-Fi"
        case .cyberwitch: return "Cyber Witch"
        case .fantasy: return "Fantasy"
        case .anime: return "Anime"
        case .arcade: return "Arcade"
        }
    }

    public var palette: ThemePalette {
        switch self {
        case .dark:
            return ThemePalette(background: hex(0x070C1A), backgroundAlt: hex(0x0C152C), panel: hex(0x10182A), panelBorder: hex(0x3B61B9), textPrimary: hex(0xE7EFFF), textSecondary: hex(0x9AABCD), textMuted: hex(0x7787AB), accentBlue: hex(0x72B0FF), accentCyan: hex(0x22DCB7), accentGold: hex(0xFFBA45), accentRose: hex(0xFF6E96))
        case .light:
            return ThemePalette(background: hex(0xF3F6FB), backgroundAlt: hex(0xE7EDF6), panel: hex(0xFFFFFF), panelBorder: hex(0xC2D0E4), textPrimary: hex(0x14203A), textSecondary: hex(0x415472), textMuted: hex(0x6B7D96), accentBlue: hex(0x0E63D4), accentCyan: hex(0x0C946E), accentGold: hex(0xB8791F), accentRose: hex(0xC23B6A))
        case .newspaper:
            return ThemePalette(background: hex(0x0B1117), backgroundAlt: hex(0x141C25), panel: hex(0x161D25), panelBorder: hex(0x96A6B6), textPrimary: hex(0xEDF2F7), textSecondary: hex(0xC5D2DF), textMuted: hex(0x9BABBA), accentBlue: hex(0xA7B2BE), accentCyan: hex(0x8E9DB0), accentGold: hex(0xAA8E54), accentRose: hex(0xC08A6A))
        case .cinema:
            return ThemePalette(background: hex(0x0B0910), backgroundAlt: hex(0x1C1321), panel: hex(0x241716), panelBorder: hex(0xDAA75F), textPrimary: hex(0xF6EFE6), textSecondary: hex(0xE7D4BD), textMuted: hex(0xB39B84), accentBlue: hex(0xC27078), accentCyan: hex(0xDAA75F), accentGold: hex(0xEEC36E), accentRose: hex(0xBA425F))
        case .scifi:
            return ThemePalette(background: hex(0x050D1A), backgroundAlt: hex(0x0D192D), panel: hex(0x0D192D), panelBorder: hex(0x7ED2FF), textPrimary: hex(0xE9F5FF), textSecondary: hex(0xCBDEEE), textMuted: hex(0x8AA3BE), accentBlue: hex(0x2CD4FF), accentCyan: hex(0x7884FF), accentGold: hex(0x6ED6FF), accentRose: hex(0x9C7BFF))
        case .cyberwitch:
            return ThemePalette(background: hex(0x070916), backgroundAlt: hex(0x141230), panel: hex(0x141230), panelBorder: hex(0xC26EFF), textPrimary: hex(0xEDF2FF), textSecondary: hex(0xCEDAF6), textMuted: hex(0x9AA3D6), accentBlue: hex(0x72DBFF), accentCyan: hex(0x4AD6FF), accentGold: hex(0xE0B0FF), accentRose: hex(0xAE64FF))
        case .fantasy:
            return ThemePalette(background: hex(0x08110F), backgroundAlt: hex(0x112320), panel: hex(0x112320), panelBorder: hex(0x93D18A), textPrimary: hex(0xE9F4EA), textSecondary: hex(0xCEE0D3), textMuted: hex(0x9BB3A2), accentBlue: hex(0x5CC78F), accentCyan: hex(0x93D18A), accentGold: hex(0xEEB554), accentRose: hex(0xE0B058))
        case .anime:
            return ThemePalette(background: hex(0x08081A), backgroundAlt: hex(0x22123A), panel: hex(0x22123A), panelBorder: hex(0xF26CD1), textPrimary: hex(0xF1F5FF), textSecondary: hex(0xE3D7F6), textMuted: hex(0xB0A5D6), accentBlue: hex(0x6ABBFF), accentCyan: hex(0x58D8FF), accentGold: hex(0xFF5CBD), accentRose: hex(0xFF5CB0))
        case .arcade:
            return ThemePalette(background: hex(0x050912), backgroundAlt: hex(0x0A181E), panel: hex(0x0A181E), panelBorder: hex(0x5BFFCB), textPrimary: hex(0xE6FAFF), textSecondary: hex(0xBDE1EE), textMuted: hex(0x8AB0BE), accentBlue: hex(0x54E9FF), accentCyan: hex(0x4CFFB0), accentGold: hex(0xFF4CE6), accentRose: hex(0xFF4CE6))
        }
    }
}

/// Live theme + font-size settings, persisted and shared across the app.
@MainActor
public final class ThemeSettings: ObservableObject {
    public static let shared = ThemeSettings()

    @AppStorage("ai_news_vibe") public var vibeRaw: String = AINewsVibe.dark.rawValue {
        didSet { applyAppAppearance() }
    }
    @AppStorage("ai_news_app_font_size") public var appFontSizeRaw: String = AINewsFontSize.medium.rawValue {
        didSet { applyAppAppearance() }
    }
    @AppStorage("ai_news_widget_font_size") public var widgetFontSizeRaw: String = AINewsFontSize.medium.rawValue {
        didSet { notifyChanged() }
    }

    /// Bumped on every change so views can key on it and fully re-render.
    @Published public private(set) var revision = 0

    public var vibe: AINewsVibe {
        get { AINewsVibe(rawValue: vibeRaw) ?? .dark }
        set { vibeRaw = newValue.rawValue }
    }
    public var appFontSize: AINewsFontSize {
        get { AINewsFontSize(rawValue: appFontSizeRaw) ?? .medium }
        set { appFontSizeRaw = newValue.rawValue }
    }
    public var widgetFontSize: AINewsFontSize {
        get { AINewsFontSize(rawValue: widgetFontSizeRaw) ?? .medium }
        set { widgetFontSizeRaw = newValue.rawValue }
    }

    public init() {
        migrateLegacyFontSizeIfNeeded()
        AINewsTheme.palette = vibe.palette
        AINewsTheme.fontScale = appFontSize.scale
    }

    private func migrateLegacyFontSizeIfNeeded() {
        let defaults = UserDefaults.standard
        guard let legacy = defaults.string(forKey: AINewsFontPreferenceStore.legacyFontSizeKey) else { return }
        if defaults.string(forKey: AINewsFontPreferenceStore.appFontSizeKey) == nil {
            defaults.set(legacy, forKey: AINewsFontPreferenceStore.appFontSizeKey)
        }
        if defaults.string(forKey: AINewsFontPreferenceStore.widgetFontSizeKey) == nil {
            defaults.set(legacy, forKey: AINewsFontPreferenceStore.widgetFontSizeKey)
        }
        appFontSizeRaw = defaults.string(forKey: AINewsFontPreferenceStore.appFontSizeKey) ?? legacy
        widgetFontSizeRaw = defaults.string(forKey: AINewsFontPreferenceStore.widgetFontSizeKey) ?? legacy
    }

    private func applyAppAppearance() {
        AINewsTheme.palette = vibe.palette
        AINewsTheme.fontScale = appFontSize.scale
        notifyChanged()
    }

    private func notifyChanged() {
        revision += 1
        objectWillChange.send()
    }
}

public enum AINewsFontPreferenceStore {
    public static let legacyFontSizeKey = "ai_news_font_size"
    public static let appFontSizeKey = "ai_news_app_font_size"
    public static let widgetFontSizeKey = "ai_news_widget_font_size"

    public static func storedAppFontSize(defaultingTo fallback: AINewsFontSize = .medium) -> AINewsFontSize {
        storedFontSize(for: appFontSizeKey, fallbackKey: legacyFontSizeKey, defaultingTo: fallback)
    }

    public static func storedWidgetFontSize(defaultingTo fallback: AINewsFontSize = .medium) -> AINewsFontSize {
        storedFontSize(for: widgetFontSizeKey, fallbackKey: legacyFontSizeKey, defaultingTo: fallback)
    }

    private static func storedFontSize(for key: String, fallbackKey: String, defaultingTo fallback: AINewsFontSize) -> AINewsFontSize {
        let defaults = UserDefaults.standard
        let raw = defaults.string(forKey: key) ?? defaults.string(forKey: fallbackKey)
        return raw.flatMap(AINewsFontSize.init(rawValue:)) ?? fallback
    }
}

public enum AINewsFontSize: String, CaseIterable, Sendable {
    case small, medium, large, xlarge

    public var displayName: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .xlarge: return "Extra Large"
        }
    }
    /// Multiplier applied to explicit font sizes.
    public var scale: CGFloat {
        switch self {
        case .small: return 0.8
        case .medium: return 1.0
        case .large: return 1.55
        case .xlarge: return 2.15
        }
    }
    /// Matching Dynamic Type size so semantic fonts (.headline/.body/.caption) scale too.
    public var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .small: return .xSmall
        case .medium: return .large
        case .large: return .accessibility1
        case .xlarge: return .accessibility4
        }
    }
}

public enum AINewsTheme {
    /// The active palette. Swapped by ThemeSettings; views re-read it on re-render.
    public static var palette: ThemePalette = AINewsVibe.dark.palette
    /// Multiplier for explicit `.system(size:)` fonts.
    public static var fontScale: CGFloat = 1.0

    public static var background: Color { palette.background }
    public static var backgroundAlt: Color { palette.backgroundAlt }
    public static var panel: Color { palette.panel }
    public static var panelBorder: Color { palette.panelBorder }
    public static var textPrimary: Color { palette.textPrimary }
    public static var textSecondary: Color { palette.textSecondary }
    public static var textMuted: Color { palette.textMuted }
    public static var accentBlue: Color { palette.accentBlue }
    public static var accentCyan: Color { palette.accentCyan }
    public static var accentGold: Color { palette.accentGold }
    public static var accentRose: Color { palette.accentRose }

    public static var cardGradient: LinearGradient {
        LinearGradient(colors: [backgroundAlt, panel], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// A size-scaled system font, so explicit sizes honor the font-size setting.
    public static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size * fontScale, weight: weight)
    }

    public static func caption2(weight: Font.Weight = .regular) -> Font {
        font(11, weight: weight)
    }

    public static func caption(weight: Font.Weight = .regular) -> Font {
        font(12.5, weight: weight)
    }

    public static func body(weight: Font.Weight = .regular) -> Font {
        font(15.5, weight: weight)
    }

    public static func subheadline(weight: Font.Weight = .regular) -> Font {
        font(16.5, weight: weight)
    }

    public static func headline(weight: Font.Weight = .semibold) -> Font {
        font(18, weight: weight)
    }

    public static func title3(weight: Font.Weight = .semibold) -> Font {
        font(24, weight: weight)
    }

    public static func title2(weight: Font.Weight = .bold) -> Font {
        font(29, weight: weight)
    }
}

/// The themed app background: the base color plus two per-vibe colored glows, so
/// each theme reads as visually distinct (purple for Cyber Witch, blue for Sci-Fi…)
/// instead of every dark theme looking near-black.
public struct AINewsBackground: View {
    public init() {}
    public var body: some View {
        ZStack {
            AINewsTheme.background
            RadialGradient(
                gradient: Gradient(colors: [AINewsTheme.panelBorder.opacity(0.30), .clear]),
                center: UnitPoint(x: 0.0, y: -0.05), startRadius: 0, endRadius: 760
            )
            RadialGradient(
                gradient: Gradient(colors: [AINewsTheme.accentCyan.opacity(0.20), .clear]),
                center: UnitPoint(x: 1.0, y: 0.05), startRadius: 0, endRadius: 760
            )
        }
        .ignoresSafeArea()
    }
}

/// A rounded, square cover thumbnail that loads asynchronously and degrades to a
/// placeholder while loading or on failure.
#if canImport(AppKit)
/// Process-wide cache so a thumbnail loaded once stays put across re-renders and
/// the widget's periodic refresh (AsyncImage re-fetches and blanks on every re-render).
private final class ThumbnailCache {
    static let shared = NSCache<NSURL, NSImage>()
}
#endif

public struct StoryThumbnail: View {
    private let url: URL?
    private let fillWidth: Bool
    private let dimension: CGFloat
    private let corners: CGFloat
    #if canImport(AppKit)
    @State private var image: NSImage?
    @State private var failed = false
    #endif

    /// Square thumbnail. A nil URL renders the placeholder.
    public init(url: URL?, size: CGFloat = 72) {
        self.url = url
        self.fillWidth = false
        self.dimension = size
        self.corners = 10
    }

    /// Full-width hero image of a fixed height.
    public init(url: URL?, heroHeight: CGFloat, corners: CGFloat = 0) {
        self.url = url
        self.fillWidth = true
        self.dimension = heroHeight
        self.corners = corners
    }

    public var body: some View {
        content
            .frame(maxWidth: fillWidth ? .infinity : dimension)
            .frame(height: dimension)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: corners, style: .continuous))
    }

    /// Themed placeholder shown when there's no cover, or while loading / on failure.
    private var placeholder: some View {
        LinearGradient(colors: [AINewsTheme.panel, AINewsTheme.background],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(
                Image(systemName: "newspaper")
                    .font(.system(size: max(14, dimension * 0.34)))
                    .foregroundStyle(AINewsTheme.textMuted.opacity(0.55))
            )
    }

    @ViewBuilder
    private var content: some View {
        #if canImport(AppKit)
        if let url {
            // Read the cache synchronously so a loaded image survives re-renders.
            if let resolved = image ?? ThumbnailCache.shared.object(forKey: url as NSURL) {
                Image(nsImage: resolved).resizable().aspectRatio(contentMode: .fill)
            } else if failed {
                placeholder
            } else {
                placeholder.overlay(ProgressView().controlSize(.small))
                    .task(id: url) { await load(url) }
            }
        } else {
            placeholder
        }
        #else
        placeholder
        #endif
    }

    #if canImport(AppKit)
    @MainActor
    private func load(_ url: URL) async {
        if let cached = ThumbnailCache.shared.object(forKey: url as NSURL) {
            image = cached
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let nsImage = NSImage(data: data) else { failed = true; return }
            ThumbnailCache.shared.setObject(nsImage, forKey: url as NSURL)
            image = nsImage
        } catch {
            failed = true
        }
    }
    #endif
}

/// A small colored pill for a story's mood/sentiment.
public struct MoodChip: View {
    private let mood: String
    public init(mood: String) { self.mood = mood }

    private var color: Color {
        let m = mood.lowercased()
        if m.contains("posi") || m.contains("optim") || m.contains("hope") || m.contains("upbeat") { return AINewsTheme.accentCyan }
        if m.contains("neg") || m.contains("crit") || m.contains("anger") || m.contains("fear") || m.contains("sad") || m.contains("alarm") { return AINewsTheme.accentRose }
        if m.contains("neutral") || m.contains("factual") { return AINewsTheme.textMuted }
        return AINewsTheme.accentGold
    }

    public var body: some View {
        Text(mood.capitalized)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.18))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

/// Modern elevated card style: subtle vertical gradient, hairline accent border,
/// and a soft shadow for depth — readable (unlike translucent glass over dark).
public extension View {
    func aiNewsCardStyle(cornerRadius: CGFloat = 16) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(LinearGradient(colors: [AINewsTheme.panel, AINewsTheme.background],
                                         startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AINewsTheme.panelBorder.opacity(0.5), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: Color.black.opacity(0.28), radius: 9, x: 0, y: 3)
    }

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
