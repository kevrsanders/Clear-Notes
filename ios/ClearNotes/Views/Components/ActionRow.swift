import SwiftUI

/// One action, with a checkbox, owner and due date. Suggested actions show accept and dismiss buttons.
struct ActionRow: View {
    @Bindable var action: ActionItem
    var showsMeeting = false
    var onShowSource: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if action.status == .suggested {
                Image(systemName: "sparkles")
                    .foregroundStyle(.tint)
                    .frame(width: 24, height: 24)
            } else {
                Button {
                    withAnimation(.snappy) {
                        action.status = action.status == .done ? .open : .done
                    }
                } label: {
                    Image(systemName: action.status == .done ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(action.status == .done ? Color.green : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(action.status == .done ? "Mark as not done" : "Mark as done")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(action.text)
                    .font(.body)
                    .strikethrough(action.status == .done)
                    .foregroundStyle(action.status == .done ? .secondary : .primary)

                let hasDetails = action.owner != nil || action.due != nil || showsMeeting || onShowSource != nil
                if hasDetails {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            if let owner = action.owner {
                                Chip(text: owner, systemImage: "person.fill", tint: .indigo)
                            }
                            if let due = action.due {
                                Chip(text: due, systemImage: "calendar", tint: .orange)
                            }
                            if showsMeeting, let meeting = action.meeting {
                                Chip(text: meeting.title, systemImage: "waveform")
                            }
                            if let onShowSource {
                                Button(action: onShowSource) {
                                    Chip(text: "Source", systemImage: "text.quote", tint: .accentColor)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if action.status == .suggested {
                    HStack(spacing: 10) {
                        Button {
                            withAnimation(.snappy) { action.status = .open }
                        } label: {
                            Label("Accept", systemImage: "checkmark")
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            withAnimation(.snappy) { action.status = .dismissed }
                        } label: {
                            Label("Dismiss", systemImage: "xmark")
                        }
                        .buttonStyle(.bordered)
                        .tint(.secondary)
                    }
                    .controlSize(.small)
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}
