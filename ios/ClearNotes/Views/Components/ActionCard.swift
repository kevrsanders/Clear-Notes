import SwiftUI

/// One action: status, text, owner, due date and source. Suggested actions show Accept and Dismiss.
struct ActionCard: View {
    @Bindable var action: ActionItem
    var onShowSource: (() -> Void)?
    /// When set, the action can be turned into a decision, for one that was really something agreed.
    var onMakeDecision: (() -> Void)?

    /// The speaker whose name matches the owner, so the owner uses their colour.
    private var ownerSpeaker: Speaker? {
        guard let owner = action.owner?.lowercased() else { return nil }
        return action.meeting?.speakers.first { $0.name?.lowercased() == owner }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                leading
                VStack(alignment: .leading, spacing: 8) {
                    Text(action.text)
                        .font(action.status == .done ? .body : .body.weight(.medium))
                        .strikethrough(action.status == .done)
                        .foregroundStyle(action.status == .done ? Theme.textSecondary : Color.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    details
                }
                Spacer(minLength: 0)
            }

            if action.status == .suggested {
                FlowLayout(spacing: 8) {
                    Button {
                        withAnimation(.snappy) { action.status = .open }
                    } label: {
                        Label("Accept", systemImage: "checkmark")
                    }
                    .buttonStyle(PrimaryButtonStyle(compact: true))

                    Button {
                        withAnimation(.snappy) { action.status = .dismissed }
                    } label: {
                        Label("Dismiss", systemImage: "xmark")
                    }
                    .buttonStyle(SecondaryButtonStyle(compact: true))

                    if let onMakeDecision {
                        Button {
                            withAnimation(.snappy) { onMakeDecision() }
                        } label: {
                            Label("Decision", systemImage: "signpost.right")
                        }
                        .buttonStyle(SecondaryButtonStyle(compact: true))
                        .accessibilityLabel("It's a decision, not an action")
                    }
                }
                .padding(.leading, 44)
            }
        }
        .cardStyle(padding: 16)
        .contextMenu {
            if let onMakeDecision {
                Button {
                    withAnimation(.snappy) { onMakeDecision() }
                } label: {
                    Label("Make it a decision", systemImage: "signpost.right")
                }
            }
        }
    }

    @ViewBuilder
    private var leading: some View {
        if action.status == .suggested {
            IconTile(systemName: "sparkles", tint: nil, size: 32)
                .accessibilityLabel("Suggested by AI")
        } else {
            Button {
                withAnimation(.snappy) {
                    action.status = action.status == .done ? .open : .done
                }
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(action.status == .done ? Theme.success : Theme.textTertiary, lineWidth: 2)
                    if action.status == .done {
                        Circle().fill(Theme.success)
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: action.status == .done)
            .accessibilityLabel(action.status == .done ? "Mark as not done" : "Mark as done")
        }
    }

    @ViewBuilder
    private var details: some View {
        if action.owner != nil || action.due != nil || onShowSource != nil || action.markID != nil {
            FlowLayout(spacing: 6) {
                if action.markID != nil {
                    Chip(text: "Marked", systemImage: "hand.tap.fill", tint: Theme.success)
                        .accessibilityLabel("You marked this while recording")
                }
                if let owner = action.owner {
                    ownerChip(owner)
                }
                if let due = action.due {
                    Chip(text: due, systemImage: "calendar", tint: Theme.warning)
                }
                if let onShowSource {
                    Button(action: onShowSource) {
                        Chip(text: "Source", systemImage: "quote.opening", tint: Theme.brand)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows where this was said in the transcript")
                }
            }
        }
    }

    /// Owner as a capsule: a small avatar in the speaker's colour plus the name.
    private func ownerChip(_ owner: String) -> some View {
        let color = ownerSpeaker.map { Theme.speakerColor(number: $0.number) } ?? Color(hex: 0x8E8E9A)
        return HStack(spacing: 5) {
            Avatar(name: owner, color: color, size: 18)
            Text(owner)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.leading, 3)
        .padding(.trailing, 9)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
    }
}
