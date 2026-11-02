import SwiftUI
import UIKit

/// Design tokens from docs/design-system.md.
enum Theme {
    static let background = Color.dynamic(light: 0xF6F6FA, dark: 0x0A0A0F)
    static let surface = Color.dynamic(light: 0xFFFFFF, dark: 0x16161D)
    /// Selected pill thumb: white in light mode, a translucent white in dark mode so it shows on glass.
    static let surfaceRaised = Color.dynamic(light: 0xFFFFFF, dark: 0xFFFFFF, darkAlpha: 0.14)
    static let stroke = Color.dynamic(light: 0x0F0F1E, lightAlpha: 0.06, dark: 0xFFFFFF, darkAlpha: 0.07)
    static let textSecondary = Color.dynamic(light: 0x6B6B78, dark: 0x9A9AA8)
    static let textTertiary = Color.dynamic(light: 0xA3A3AF, dark: 0x5C5C68)
    static let brand = Color.accentColor
    static let success = Color.dynamic(light: 0x22C55E, dark: 0x30D158)
    static let warning = Color.dynamic(light: 0xD97706, dark: 0xFFB020)
    static let record = Color(hex: 0xFF4D6A)

    static let brandGradient = LinearGradient(
        colors: [Color(hex: 0x7C5CFF), Color(hex: 0x4F7BFF)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let recordGradient = LinearGradient(
        colors: [Color(hex: 0xFF7A59), Color(hex: 0xFF3D71)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let speakerColors: [Color] = [0x7C5CFF, 0x14B8A6, 0xFB923C, 0xEC4899, 0x3B82F6, 0x84CC16, 0xEAB308, 0xEF4444]
        .map { Color(hex: $0) }

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

    /// Liquid Glass on iOS 26, translucent material on earlier versions. For floating controls.
    @ViewBuilder
    func glass<S: Shape>(in shape: S) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Theme.stroke, lineWidth: 1))
        }
        #else
        self.background(.ultraThinMaterial, in: shape)
            .overlay(shape.stroke(Theme.stroke, lineWidth: 1))
        #endif
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

/// Screen background: the base colour with soft colour glows across the top.
struct GlowBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        ZStack(alignment: .top) {
            Theme.background
            ZStack {
                Circle()
                    .fill(Color(hex: 0x8B7BFF).opacity(dark ? 0.22 : 0.28))
                    .frame(width: 320, height: 320)
                    .offset(x: -130, y: -80)
                Circle()
                    .fill(Color(hex: 0x5AB8FF).opacity(dark ? 0.16 : 0.22))
                    .frame(width: 280, height: 280)
                    .offset(x: 140, y: -110)
                Circle()
                    .fill(Color(hex: 0xFFB38A).opacity(dark ? 0.10 : 0.20))
                    .frame(width: 260, height: 260)
                    .offset(x: 40, y: 40)
            }
            .blur(radius: 80)
            .frame(height: 320)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
