import SwiftUI
import UIKit

/// Shows a follow-up draft (action list, email or plan) that the user can edit, copy or share.
struct FollowUpSheet: View {
    let kind: FollowUpKind
    let meeting: Meeting

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var source = ""
    @State private var isWriting = true
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                IconTile(systemName: kind.systemImage, tint: FollowUpStyle.tint(for: kind), size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .font(.headline)
                    Text(isWriting ? "Writing on this iPhone…" : source)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
                GlassCircleButton(systemName: "xmark", accessibilityLabel: "Close") { dismiss() }
            }

            Group {
                if isWriting {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(0..<6, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.primary.opacity(0.07))
                                .frame(height: 14)
                                .frame(maxWidth: index % 3 == 2 ? 200 : CGFloat.infinity, alignment: .leading)
                        }
                        Spacer()
                    }
                    .padding(18)
                } else {
                    TextEditor(text: $text)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.stroke))

            HStack(spacing: 10) {
                GlassCircleButton(systemName: "arrow.clockwise", accessibilityLabel: "Rewrite") {
                    Task { await write() }
                }
                .disabled(isWriting)
                Spacer()
                Button {
                    UIPasteboard.general.string = text
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(isWriting)
                ShareLink(item: text) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isWriting)
            }
            .sensoryFeedback(.success, trigger: copied)
        }
        .padding(Theme.gutter)
        .background(Theme.background)
        .task { await write() }
    }

    private func write() async {
        isWriting = true
        copied = false
        let draft = await FollowUpWriter.draft(kind, for: MeetingSnapshot(meeting))
        text = draft.text
        source = draft.source
        isWriting = false
    }
}

enum FollowUpStyle {
    static func tint(for kind: FollowUpKind) -> Color {
        switch kind {
        case .actionList: Theme.brand
        case .email: Color(hex: 0x14B8A6)
        case .projectPlan: Color(hex: 0xFB923C)
        }
    }
}
