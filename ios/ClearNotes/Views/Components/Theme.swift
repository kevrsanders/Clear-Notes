import SwiftUI
import UIKit

/// Design tokens from docs/design-system.md.
enum Theme {
    static let background = Color.dynamic(light: 0xF6F6FA, dark: 0x0A0A0F)
    static let surface = Color.dynamic(light: 0xFFFFFF, dark: 0x16161D)
    /// Selected pill thumb: white in light mode, a translucent white in dark mode.
    static let surfaceRaised = Color.dynamic(light: 0xFFFFFF, dark: 0xFFFFFF, darkAlpha: 0.14)
    /// The track the thumb slides in, a shade darker than the screen so the thumb stands out.
    static let track = Color.dynamic(light: 0x0F0F1E, lightAlpha: 0.06, dark: 0xFFFFFF, darkAlpha: 0.06)
    static let stroke = Color.dynamic(light: 0x0F0F1E, lightAlpha: 0.06, dark: 0xFFFFFF, darkAlpha: 0.07)
    static let textSecondary = Color.dynamic(light: 0x6B6B78, dark: 0x9A9AA8)
    static let textTertiary = Color.dynamic(light: 0xA3A3AF, dark: 0x5C5C68)
    /// The colour chosen in Settings → Appearance (teal by default). See `AppAccent`.
    static var brand: Color { AppAccent.current.color }
    /// Text and symbols on the brand colour or gradient: white, or dark on light accents.
    static var onBrand: Color { AppAccent.current.onColor }
    static let success = Color.dynamic(light: 0x22C55E, dark: 0x30D158)
    /// Decisions: green, or amber with the sage accent so green doesn't mean two things.
    static var decision: Color { AppAccent.current.decision }
    static let warning = Color.dynamic(light: 0xD97706, dark: 0xFFB020)
    static let record = Color(hex: 0xFF4D6A)
    /// Meeting types: a quick catch-up and a voice note. Meetings use the brand colour. Each
    /// avoids the accent, so the three stay distinct.
    static var catchUp: Color { AppAccent.current.catchUp }
    static var voiceNote: Color { AppAccent.current.voiceNote }

    static var brandGradient: LinearGradient {
        LinearGradient(colors: AppAccent.current.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static let recordGradient = LinearGradient(
        colors: [Color(hex: 0xFF7A59), Color(hex: 0xFF3D71)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// Speakers' colours in order, starting from the accent's family.
    static var speakerColors: [Color] {
        AppAccent.current.speakerColors.map { Color(hex: $0) }
    }

    static func speakerColor(number: Int) -> Color {
        speakerColors[(max(number, 1) - 1) % speakerColors.count]
    }

    static let cardRadius: CGFloat = 24
    static let gutter: CGFloat = 20
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    /// A colour with separate light and dark mode values.
    static func dynamic(light: UInt32, lightAlpha: CGFloat = 1, dark: UInt32, darkAlpha: CGFloat = 1) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkAlpha)
                : UIColor(hex: light, alpha: lightAlpha)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

// MARK: - Surfaces

extension View {
    /// Solid content card: surface fill, hairline outline and (in light mode) a soft shadow.
    func cardStyle(padding: CGFloat = 18) -> some View {
        modifier(CardStyle(padding: padding))
    }

    /// A solid control surface: the card colour with a hairline outline, no glass or blur. For
    /// buttons, the search field, tabs and floating bars.
    func panel<S: InsettableShape>(in shape: S) -> some View {
        self.background(Theme.surface, in: shape)
            .overlay(shape.strokeBorder(Theme.stroke, lineWidth: 1))
    }
}

private struct CardStyle: ViewModifier {
    var padding: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: shape)
            .overlay(shape.strokeBorder(Theme.stroke, lineWidth: 1))
            .shadow(color: colorScheme == .dark ? .clear : Color(hex: 0x1E1E3C, alpha: 0.06), radius: 12, y: 8)
    }
}

/// The app's colour, chosen in Settings → Appearance. It sets the accent (buttons, links,
/// toggles, tabs), the brand gradient, the user's avatar and the first speaker colour. Record stays red whichever is chosen.
enum AppAccent: String, CaseIterable, Identifiable {
    case teal, ocean, sage, amber, graphite

    var id: String { rawValue }

    static var current: AppAccent {
        AppAccent(rawValue: UserDefaults.standard.string(forKey: SettingsKeys.accent) ?? "") ?? .teal
    }

    var title: String {
        switch self {
        case .teal: "Teal"
        case .ocean: "Ocean"
        case .sage: "Sage"
        case .amber: "Amber"
        case .graphite: "Graphite"
        }
    }

    var color: Color {
        switch self {
        case .teal: Color.dynamic(light: 0x0F9C8C, dark: 0x3CCFBE)
        case .ocean: Color.dynamic(light: 0x1F6FD1, dark: 0x5AA9F5)
        case .sage: Color.dynamic(light: 0x1F8A5B, dark: 0x5CC796)
        case .amber: Color.dynamic(light: 0xB9770E, dark: 0xF5B642)
        case .graphite: Color.dynamic(light: 0x2B2B33, dark: 0xD1D1D8)
        }
    }

    /// Text on the accent: dark where the accent is light.
    var onColor: Color {
        switch self {
        case .teal, .ocean, .sage: Color.white
        case .amber: Color.dynamic(light: 0xFFFFFF, dark: 0x1B1205)
        case .graphite: Color.dynamic(light: 0xFFFFFF, dark: 0x0A0A0F)
        }
    }

    var gradient: [Color] {
        switch self {
        case .teal: [Color(hex: 0x14B8A6), Color(hex: 0x2E8FD8)]
        case .ocean: [Color(hex: 0x3B8BEB), Color(hex: 0x22B8CF)]
        case .sage: [Color(hex: 0x2FA36F), Color(hex: 0x8BBF4A)]
        case .amber: [Color(hex: 0xF5B642), Color(hex: 0xF0803C)]
        case .graphite: [Color.dynamic(light: 0x3A3A45, dark: 0xF2F2F6), Color.dynamic(light: 0x1C1C24, dark: 0xBDBDC7)]
        }
    }

    var speakerColors: [UInt32] {
        let rest: [UInt32] = [0x14B8A6, 0xFB923C, 0xEC4899, 0x3B82F6, 0x84CC16, 0xEAB308, 0xEF4444, 0x8B5CF6]
        let first: UInt32 = switch self {
        case .teal: 0x0FA595
        case .ocean: 0x2F7FE0
        case .sage: 0x2FA36F
        case .amber: 0xE59A1C
        case .graphite: 0x8E8E9C
        }
        // Without the one nearest the accent, so the first two speakers never look alike.
        let similar: UInt32 = switch self {
        case .teal: 0x14B8A6
        case .ocean: 0x3B82F6
        case .sage: 0x84CC16
        case .amber: 0xEAB308
        case .graphite: 0x8B5CF6
        }
        return [first] + rest.filter { $0 != similar }
    }

    var decision: Color {
        self == .sage ? Color.dynamic(light: 0xD97706, dark: 0xF5B642) : Theme.success
    }

    var catchUp: Color {
        self == .teal ? Color.dynamic(light: 0x2563EB, dark: 0x60A5FA) : Color.dynamic(light: 0x0E9AB2, dark: 0x40C8E0)
    }

    var voiceNote: Color {
        self == .amber ? Color.dynamic(light: 0xDB2777, dark: 0xF472B6) : Color.dynamic(light: 0xE07B00, dark: 0xFFA53D)
    }

    /// Colours system controls drawn by UIKit (alerts, menus) to match.
    @MainActor
    static func applyTint() {
        let tint = UIColor(current.color)
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                window.tintColor = tint
            }
        }
    }
}

/// Screen background: the plain base colour, no glow.
struct ScreenBackground: View {
    var body: some View {
        Theme.background
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}
