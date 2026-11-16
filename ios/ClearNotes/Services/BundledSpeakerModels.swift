import CoreML
import Foundation
#if canImport(FluidAudio)
import FluidAudio
#endif

/// The speaker-identification models, built into the app (the SpeakerModels folder, filled at
/// build time by scripts/fetch_speaker_models.py). They're loaded from the app itself, so
/// identifying speakers never downloads anything or contacts anyone.
enum BundledSpeakerModels {
    static let folderName = "SpeakerModels"
    static let segmentation = "Segmentation.mlmodelc"
    static let fbank = "FBank.mlmodelc"
    static let embedding = "Embedding.mlmodelc"
    static let pldaRho = "PldaRho.mlmodelc"
    static let pldaParameters = "plda-parameters.json"
    static let requiredFiles = [segmentation, fbank, embedding, pldaRho, pldaParameters]

    static var directory: URL? {
        Bundle.main.url(forResource: folderName, withExtension: nil)
    }

    /// Whether this build of the app includes every model file. Checked once, as the app's own
    /// files don't change.
    static let isAvailable: Bool = {
        guard let directory = BundledSpeakerModels.directory else { return false }
        return BundledSpeakerModels.requiredFiles.allSatisfy {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
    }()

    /// Earlier versions downloaded the models into Application Support. They're built in now, so
    /// that copy (tens of MB) is deleted.
    static func removeOldDownload() {
        #if canImport(FluidAudio)
        let old = OfflineDiarizerModels.defaultModelsDirectory().appendingPathComponent("speaker-diarization-coreml")
        if FileManager.default.fileExists(atPath: old.path) {
            try? FileManager.default.removeItem(at: old)
        }
        #endif
    }

    enum LoadError: LocalizedError {
        case missing
        case badParameters

        var errorDescription: String? {
            switch self {
            case .missing: "The speaker models aren't included in this build of Clear Notes."
            case .badParameters: "The speaker models in this build of Clear Notes couldn't be read."
            }
        }
    }

    /// The PLDA scaling factors stored with the models: base64 Float32 values at
    /// tensors.psi.data_base64, read as FluidAudio reads them.
    static func pldaPsi(from data: Data) throws -> [Double] {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tensors = root["tensors"] as? [String: Any],
            let psi = tensors["psi"] as? [String: Any],
            let base64 = psi["data_base64"] as? String,
            let decoded = Data(base64Encoded: base64, options: .ignoreUnknownCharacters)
        else { throw LoadError.badParameters }
        let count = decoded.count / MemoryLayout<Float>.size
        guard count > 0 else { throw LoadError.badParameters }
        var floats = [Float](repeating: 0, count: count)
        _ = floats.withUnsafeMutableBytes { decoded.copyBytes(to: $0) }
        return floats.map { Double($0) }
    }

    #if canImport(FluidAudio)
    /// Loads the models from the app, with the same settings FluidAudio uses for its own downloads:
    /// the filter bank on the CPU (fastest there), the rest wherever Core ML runs them best.
    static func load() async throws -> OfflineDiarizerModels {
        guard isAvailable, let directory = directory else { throw LoadError.missing }
        let start = Date()

        let anywhere = MLModelConfiguration()
        anywhere.computeUnits = .all
        anywhere.allowLowPrecisionAccumulationOnGPU = true
        let cpu = MLModelConfiguration()
        cpu.computeUnits = .cpuOnly

        func model(_ name: String, _ configuration: MLModelConfiguration) async throws -> MLModel {
            try await MLModel.load(contentsOf: directory.appendingPathComponent(name), configuration: configuration)
        }
        let segmentationModel = try await model(segmentation, anywhere)
        let fbankModel = try await model(fbank, cpu)
        let embeddingModel = try await model(embedding, anywhere)
        let pldaRhoModel = try await model(pldaRho, anywhere)
        let psi = try pldaPsi(from: Data(contentsOf: directory.appendingPathComponent(pldaParameters)))

        return OfflineDiarizerModels(
            segmentationModel: segmentationModel,
            fbankModel: fbankModel,
            embeddingModel: embeddingModel,
            pldaRhoModel: pldaRhoModel,
            pldaPsi: psi,
            compilationDuration: Date().timeIntervalSince(start)
        )
    }
    #endif
}

/// Clear Notes downloads nothing unless the user asks. The model library (FluidAudio) can fetch
/// models from Hugging Face, so that's blocked from launch, and only allowed while the user is
/// downloading the More accurate transcripts model in Settings.
enum ModelDownloads {
    static var isBlocked: Bool {
        get {
            #if canImport(FluidAudio)
            ModelHub.offlineMode
            #else
            true
            #endif
        }
        set {
            #if canImport(FluidAudio)
            ModelHub.offlineMode = newValue
            #endif
        }
    }

    /// Called at launch, before any model is loaded.
    static func blockByDefault() {
        isBlocked = true
    }
}
