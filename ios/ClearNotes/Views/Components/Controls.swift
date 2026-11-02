import SwiftUI

/// Small uppercase label above a title or section.
struct Eyebrow: View {
    var text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(Theme.textSecondary)
    }
}

/// Small rounded label used for owners, due dates and status.
struct Chip: View {
    var text: String
    var systemImage: String?
    var tint: Color = Theme.textSecondary

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .bold))
            }
            Text(text)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

/// SF Symbol on a rounded square, filled with the brand gradient (AI content) or a tint.
struct IconTile: View {
    var systemName: String
    var tint: Color?
    var size: CGFloat = 28

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
        Image(systemName: systemName)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(tint == nil ? Color.white : tint!)
            .frame(width: size, height: size)
            .background {
                if let tint {
                    shape.fill(tint.opacity(0.14))
                } else {
                    shape.fill(Theme.brandGradient)
                }
            }
    }
}

/// Header row used at the top of cards.
struct CardHeader<Accessory: View>: View {
    var title: String
    var systemImage: String
    var tint: Color?
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 10) {
            IconTile(systemName: systemImage, tint: tint)
            Text(title)
                .font(.headline)
            Spacer(minLength: 0)
            accessory
        }
    }
}

extension CardHeader where Accessory == EmptyView {
    init(title: String, systemImage: String, tint: Color? = nil) {
        self.init(title: title, systemImage: systemImage, tint: tint) { EmptyView() }
    }
}

/// A 40pt glass circle for close, back and more buttons.
struct GlassCircleButton: View {
    var systemName: String
    var accessibilityLabel: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 40, height: 40)
                .glass(in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Capsule filled with the brand gradient.
struct PrimaryButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font((compact ? Font.subheadline : Font.body).weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 14 : 22)
            .padding(.vertical, compact ? 8 : 14)
            .background(Theme.brandGradient, in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

/// Quiet capsule for secondary choices.
struct SecondaryButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font((compact ? Font.subheadline : Font.body).weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, compact ? 14 : 22)
            .padding(.vertical, compact ? 8 : 14)
            .background(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.06), in: Capsule())
    }
}

/// Replaces segmented controls: a glass track with a sliding raised thumb.
struct PillTabs<Value: Hashable>: View {
    struct Item {
        var value: Value
        var title: String
        var badge: Int = 0
    }

    var items: [Item]
    @Binding var selection: Value
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.value) { item in
                let isSelected = item.value == selection
                Button {
                    withAnimation(.snappy(duration: 0.3)) { selection = item.value }
                } label: {
                    HStack(spacing: 5) {
                        Text(item.title)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if item.badge > 0 {
                            Text("\(item.badge)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.brand, in: Capsule())
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.primary : Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(Theme.surfaceRaised)
                                .shadow(color: .black.opacity(0.10), radius: 6, y: 2)
                                .matchedGeometryEffect(id: "thumb", in: namespace)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .glass(in: Capsule())
    }
}

/// Small card with a label, a big number and a hint.
struct StatTile: View {
    var title: String
    var value: String
    var hint: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 28, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(hint)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .cardStyle(padding: 14)
    }
}

/// The floating "Record" button on the home screen.
struct RecordButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.22), in: Circle())
                Text("Record")
                    .font(.headline)
            }
            .foregroundStyle(.white)
            .padding(.leading, 12)
            .padding(.trailing, 26)
            .frame(height: 60)
            .background(Theme.recordGradient, in: Capsule())
            .shadow(color: Theme.record.opacity(0.4), radius: 18, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Record a meeting")
        .accessibilityHint("Starts transcribing a meeting on this iPhone")
    }
}

/// Lays out children left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var width: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            width = max(width, x + size.width)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
