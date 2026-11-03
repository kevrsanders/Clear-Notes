import Foundation
import SwiftData

/// A remembered voice: a name and a few voiceprints (speaker embeddings) from earlier meetings.
///
/// Voiceprints are biometric data. They are only saved when the user turns on Remember voices
/// and confirms the person agreed, they never leave the iPhone, and they can be deleted at any time.
@Model
final class VoiceProfile {
    @Attribute(.unique) var profileID: UUID
    var name: String
    /// Up to `VoiceLibrary.maximumSamples` voiceprints, newest last.
    var samples: [[Float]]
    /// How many times the user has confirmed this voice; auto-naming needs a few.
    var confirmations: Int
    var consentedAt: Date
    var lastHeardAt: Date

    init(name: String, sample: [Float], at date: Date = .now) {
        self.profileID = UUID()
        self.name = name
        self.samples = [sample]
        self.confirmations = 1
        self.consentedAt = date
        self.lastHeardAt = date
    }
}
