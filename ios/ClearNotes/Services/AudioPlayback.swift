import AVFoundation
import Observation

/// Plays a meeting's kept recording, with seeking and playback speed.
@MainActor
@Observable
final class AudioPlayback {
    static let rates: [Float] = [1, 1.5, 2]

    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var rate: Float = 1
    private(set) var isLoaded = false

    private var player: AVAudioPlayer?
    private var loadedURL: URL?
    private var ticker: Timer?

    func load(_ url: URL) {
        guard loadedURL != url else { return }
        stop()
        player = try? AVAudioPlayer(contentsOf: url)
        player?.enableRate = true
        player?.prepareToPlay()
        loadedURL = url
        duration = player?.duration ?? 0
        currentTime = 0
        isLoaded = player != nil
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    /// Plays from `time`, or from the current position.
    func play(from time: TimeInterval? = nil) {
        guard let player else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio)
        try? session.setActive(true)
        if let time {
            player.currentTime = max(0, min(time, player.duration))
            currentTime = player.currentTime
        }
        player.rate = rate
        player.play()
        isPlaying = true
        startTicker()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTicker()
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        player.currentTime = max(0, min(time, player.duration))
        currentTime = player.currentTime
    }

    /// Steps through 1×, 1.5× and 2×.
    func cycleRate() {
        let index = Self.rates.firstIndex(of: rate) ?? 0
        rate = Self.rates[(index + 1) % Self.rates.count]
        player?.rate = rate
    }

    func stop() {
        player?.stop()
        isPlaying = false
        stopTicker()
        if loadedURL != nil {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    /// Releases the file, e.g. before it is deleted.
    func unload() {
        stop()
        player = nil
        loadedURL = nil
        isLoaded = false
        duration = 0
        currentTime = 0
    }

    private func startTicker() {
        stopTicker()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard let player else { return }
        currentTime = player.currentTime
        if !player.isPlaying {
            // Reached the end.
            isPlaying = false
            stopTicker()
        }
    }
}
