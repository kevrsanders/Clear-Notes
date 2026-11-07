import SwiftUI

/// A person's initials on their colour. Unnamed speakers show their number on a dashed ring.
struct Avatar: View {
    var name: String?
    var color: Color
    var size: CGFloat = 32
    /// Shown when there is no name, e.g. the speaker number.
    var placeholder = "?"
    /// The initials' colour: white on speaker colours, or the accent's text colour on the accent.
    var textColor: Color = .white

    var body: some View {
        ZStack {
            if let initials = Self.initials(of: name) {
                Circle().fill(color)
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(textColor)
            } else {
                Circle().fill(color.opacity(0.14))
                Circle().strokeBorder(color, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                Text(placeholder)
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundStyle(color)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(name ?? "Unnamed speaker")
    }

    nonisolated static func initials(of name: String?) -> String? {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first)
        return String(letters).uppercased()
    }
}

extension Avatar {
    init(speaker: Speaker, size: CGFloat = 32) {
        self.init(
            name: speaker.name,
            color: Theme.speakerColor(number: speaker.number),
            size: size,
            placeholder: "\(speaker.number)"
        )
    }
}

/// Overlapping avatars with a "+N" overflow.
struct AvatarStack: View {
    var speakers: [Speaker]
    var size: CGFloat = 26
    var limit = 4

    var body: some View {
        HStack(spacing: -size * 0.3) {
            ForEach(speakers.prefix(limit)) { speaker in
                Avatar(speaker: speaker, size: size)
                    .padding(2)
                    .background(Theme.surface, in: Circle())
            }
            if speakers.count > limit {
                Text("+\(speakers.count - limit)")
                    .font(.system(size: size * 0.36, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: size, height: size)
                    .background(Theme.background, in: Circle())
                    .padding(2)
                    .background(Theme.surface, in: Circle())
            }
        }
    }
}
