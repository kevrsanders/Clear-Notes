import SwiftUI

/// Rolling bar graph of recent microphone levels.
struct LevelMeter: View {
    var levels: [Float]
    var isActive: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(isActive ? Theme.record : Color.secondary.opacity(0.4))
                    .frame(width: 4, height: max(4, CGFloat(level) * 56))
            }
        }
        .frame(height: 60)
        .animation(.easeOut(duration: 0.12), value: levels)
        .accessibilityHidden(true)
    }
}
