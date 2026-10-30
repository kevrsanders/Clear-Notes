import SwiftUI

enum Theme {
    static let record = Color(red: 0.93, green: 0.26, blue: 0.32)
    static let card = Color(.secondarySystemGroupedBackground)
    static let canvas = Color(.systemGroupedBackground)
    static let cornerRadius: CGFloat = 18
}

/// A rounded card with an optional section title.
struct Card<Content: View>: View {
    var title: String?
    var systemImage: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Label(title, systemImage: systemImage ?? "circle")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

/// Small rounded label used for owners, due dates and status.
struct Chip: View {
    var text: String
    var systemImage: String
    var tint: Color = .secondary

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
    }
}
