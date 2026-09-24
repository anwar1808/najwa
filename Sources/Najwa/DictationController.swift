import AppKit

/// Orchestrates one dictation: hotkey → capture → transcribe → cleanup →
/// inject → history, while driving the HUD and menu-bar state.
final class DictationController {
    enum State { case idle, recording, working }

    var onStateChange: ((State) -> Void)?
    var onModelStatus: ((String) -> Void)?
    var onLatency: ((Double) -> Void)?   // seconds, release → text injected

    private let audio: AudioCapture
    private let hud: HUDController
    private let cleaner: Cleanup
    private let injector: TextInjector
    private let history: HistoryStore
    private let whisper: Transcriber

    private var isRecording = false
    // Audio engine start/stop stays OFF the main thread: even the ~0.1s raw
    // start (post-v0.2.0, no voice processing) would block the fn event tap,
    // which delivers on the main run loop — a blocked tap makes macOS disable
    // it and drop the key-release event.
    private let audioQueue = DispatchQueue(label: "ai.najwa.audio")

    init() {
        audio = AudioCapture()
        hud = HUDController()
        cleaner = Cleanup()
        injector = TextInjector()
        history = HistoryStore()
        whisper = WhisperKitTranscriber()
        audio.onLevel = { [weak self] level in self?.hud.update(level: level) }
        whisper.onStatus = { [weak self] msg in
            DispatchQueue.main.async { self?.onModelStatus?(msg) }
        }
        Task { await whisper.prepare() } // download/load the model at launch
    }

    func beginRecording() {
        guard !isRecording else { return }
        Permissions.requestMicrophone { [weak self] granted in
            guard let self = self else { return }
            guard granted else {
                NSLog("Najwa: microphone permission denied.")
                return
            }
            self.isRecording = true
            self.hud.show()                 // main thread, fast
            self.onStateChange?(.recording)
            self.audioQueue.async { self.audio.start() } // slow work off main
        }
    }

    func endRecording() {
        guard isRecording else { return }
        isRecording = false
        let releaseTime = ProcessInfo.processInfo.systemUptime // for latency timing
        onStateChange?(.working)

        audioQueue.async { [weak self] in
            guard let self = self else { return }
            let (samples, sampleRate) = self.audio.stop() // slow work off main
            let seconds = Double(samples.count) / max(sampleRate, 1)
            // The pill stays up, wave → breathing ن, until the text has landed.
            DispatchQueue.main.async { self.hud.beginWorking() }
            Task {
                defer { Task { @MainActor in self.onStateChange?(.idle) } }
                do {
                    let raw = try await self.whisper.transcribe(samples, sampleRate: sampleRate)
                    // Status sentinels ("[Najwa: …]") must reach the user verbatim;
                    // the LLM cleaner would rewrite them as if they were dictation.
                    let polished = raw.hasPrefix("[Najwa:")
                        ? raw
                        : await self.cleaner.polish(raw)
                    guard !polished.isEmpty else {
                        // Never fail silently: an empty transcript looks exactly
                        // like "the app is broken" unless we say we heard nothing.
                        NSLog(String(format: "Najwa: empty transcription (%.1fs audio) — nothing injected", seconds))
                        await MainActor.run { self.hud.finish(); self.hud.flash("Najwa heard nothing") }
                        return
                    }
                    // Inject off the main thread: CGEvent posting is thread-safe
                    // and a long paste (usleep per 20-char chunk) would otherwise
                    // freeze the dot mid-pulse for the whole time it types.
                    self.injector.inject(polished)
                    await MainActor.run {
                        self.history.add(polished)
                        self.hud.finish()
                    }
                    let dt = ProcessInfo.processInfo.systemUptime - releaseTime
                    NSLog(String(format: "Najwa: release→text %.0fms", dt * 1000))
                    await MainActor.run { self.onLatency?(dt) }
                } catch {
                    NSLog("Najwa: transcription failed: \(error.localizedDescription)")
                    await MainActor.run { self.hud.finish() }
                }
            }
        }
    }
}
