import Foundation
#if canImport(FluidAudio)
import FluidAudio
#endif

/// A second, more accurate transcription of the kept recording after the meeting, using NVIDIA's
/// Parakeet speech model on the iPhone (through FluidAudio). The live transcript is replaced by
/// this one. The model is a one-off download of about 450 MB, and nothing leaves the iPhone.
actor AccurateTranscriber {
    static let shared = AccurateTranscriber()

    /// Whether this build includes the model library.
    static var isSupported: Bool {
        #if canImport(FluidAudio)
        true
        #else
        false
        #endif
    }

    /// The user turned on More accurate transcripts and the model has finished downloading.
    static var isReady: Bool {
        isSupported
            && UserDefaults.standard.bool(forKey: SettingsKeys.accurateTranscripts)
            && UserDefaults.standard.bool(forKey: SettingsKeys.accurateModelsReady)
    }

    #if canImport(FluidAudio)
    private var manager: AsrManager?

    /// The English-only model is the most accurate for English; other languages use the
    /// multilingual one (25 European languages).
    private static var version: AsrModelVersion {
        Locale.current.language.languageCode == .english ? .v2 : .v3
    }
    #endif

    /// Downloads the model once and loads it. Safe to call again; later calls return straight away.
    func prepare() async throws {
        #if canImport(FluidAudio)
        guard manager == nil else { return }
        let models = try await AsrModels.downloadAndLoad(version: Self.version)
        let loaded = AsrManager(config: .default)
        try await loaded.loadModels(models)
        manager = loaded
        UserDefaults.standard.set(true, forKey: SettingsKeys.accurateModelsReady)
        #endif
    }

    /// The recording's words with their times, from the accurate model.
    func words(in url: URL) async throws -> [TimedWord] {
        #if canImport(FluidAudio)
        try await prepare()
        guard let manager else { return [] }
        var state = TdtDecoderState.make()
        let result = try await manager.transcribe(url, decoderState: &state)
        return buildWordTimings(from: result.tokenTimings ?? []).map {
            TimedWord(text: $0.word, start: $0.startTime, end: $0.endTime)
        }
        #else
        return []
        #endif
    }

    /// Deletes the downloaded model to free the space.
    func removeModels() {
        #if canImport(FluidAudio)
        manager = nil
        for version in [AsrModelVersion.v2, .v3] {
            try? FileManager.default.removeItem(at: AsrModels.defaultCacheDirectory(for: version))
        }
        #endif
        UserDefaults.standard.set(false, forKey: SettingsKeys.accurateModelsReady)
    }
}
