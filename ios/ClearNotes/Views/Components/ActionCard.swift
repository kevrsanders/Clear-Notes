import SwiftUI

/// One action: status, text, owner, due date and source. Suggested actions show Accept and Dismiss.
struct ActionCard: View {
    @Bindable var action: ActionItem
    var onShowSource: (() -> Void)?
    /// When set, the action can be turned into a decision, for one that was really something agreed.
    var onMakeDecision: (() -> Void)?
    /// When set, tapping the action (or Assign) opens it to change what, who and when.
    var onEdit: (() -> Void)?

    /// The ⋯ menu, also opened by holding the card.
    @State private var showingMenu = false

    private var hasMenu: Bool { onMakeDecision != nil || onEdit != nil || onShowSource != nil }

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
                        .contentShape(Rectangle())
                        .onTapGesture { onEdit?() }
                        .accessibilityAddTraits(onEdit == nil ? [] : .isButton)
                        .accessibilityHint(onEdit == nil ? "" : "Edit, assign or set a date")
                    details
                }
                Spacer(minLength: 0)
            }

            if action.status == .suggested {
                // One tidy row across the card: Accept, Dismiss, and ⋯ for the rest.
                HStack(spacing: 8) {
                    Button {
                        withAnimation(.snappy) { action.status = .open }
                    } label: {
                        Label("Accept", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle(compact: true))

                    Button {
                        withAnimation(.snappy) { action.status = .dismissed }
                    } label: {
                        Label("Dismiss", systemImage: "xmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle(compact: true))

                    if hasMenu {
                        Button {
                            showingMenu = true
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.primary)
                                .frame(width: 38, height: 38)
                                .background(Color.primary.opacity(0.08), in: Circle())
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("More")
                    }
                }
            }
        }
        .cardStyle(padding: 16)
        .onHoldForMenu { if hasMenu { showingMenu = true } }
        .menuSheet(isPresented: $showingMenu) {
            MenuSheet(action.text) {
                MenuGroup {
                    if let onEdit {
                        MenuRow("Edit or assign", subtitle: "What, who and by when", systemImage: "person.crop.circle.badge.plus", action: onEdit)
                    }
                    if let onMakeDecision {
                        MenuRow("It's a decision", subtitle: "Something agreed, not something to do", systemImage: "signpost.right") {
                            withAnimation(.snappy) { onMakeDecision() }
                        }
                    }
                    if let onShowSource {
                        MenuRow("Show source", subtitle: "Where it was said in the transcript", systemImage: "quote.opening", action: onShowSource)
                    }
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
        if action.owner != nil || action.due != nil || onShowSource != nil || action.markID != nil || onEdit != nil {
            FlowLayout(spacing: 6) {
                if action.markID != nil {
                    Chip(text: "Marked", systemImage: "hand.tap.fill", tint: Theme.success)
                        .accessibilityLabel("You marked this while recording")
                }
                if let owner = action.owner {
                    Button {
                        onEdit?()
                    } label: {
                        ownerChip(owner)
                    }
                    .buttonStyle(.plain)
                    .disabled(onEdit == nil)
                    .accessibilityLabel("Owner: \(owner)")
                    .accessibilityHint(onEdit == nil ? "" : "Change who's doing it")
                } else if let onEdit {
                    Button(action: onEdit) {
                        ActionChip(text: "Assign", systemImage: "person.crop.circle.badge.plus")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Assign this action")
                }
                if let due = action.due {
                    Chip(text: due, systemImage: "calendar", tint: Theme.warning)
                }
                if let onShowSource {
                    Button(action: onShowSource) {
                        ActionChip(text: "Source", systemImage: "quote.opening")
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
        // The same size and outline as the Assign and Source chips beside it.
        return HStack(spacing: 6) {
            Avatar(name: owner, color: color, size: 22)
            Text(owner)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.leading, 3)
        .padding(.trailing, 11)
        .padding(.vertical, 3)
        .background(color.opacity(0.14), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 1))
    }
}
