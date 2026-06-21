import AppKit

/// Orchestrates one dictation: hotkey → capture → transcribe → cleanup →
/// inject → history, while driving the HUD and menu-bar state.
final class DictationController {
    enum State { case idle, recording, working }

    var onStateChange: ((State) -> Void)?
    var onModelStatus: ((String) -> Void)?

    private let audio = AudioCapture()
    private let hud = HUDController()
    private let cleaner = Cleanup()
    private let injector = TextInjector()
    private let history = HistoryStore()
    private let whisper = WhisperKitTranscriber(model: "small")
    private var transcriber: Transcriber { whisper }

    private var isRecording = false

    init() {
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
            self.audio.start()
            self.hud.show()
            self.onStateChange?(.recording)
        }
    }

    func endRecording() {
        guard isRecording else { return }
        isRecording = false
        let (samples, sampleRate) = audio.stop()
        hud.hide()
        onStateChange?(.working)

        Task { [weak self] in
            guard let self = self else { return }
            defer { Task { @MainActor in self.onStateChange?(.idle) } }
            do {
                let raw = try await self.transcriber.transcribe(samples, sampleRate: sampleRate)
                let polished = await self.cleaner.polish(raw)
                guard !polished.isEmpty else { return }
                await MainActor.run {
                    self.injector.inject(polished)
                    self.history.add(polished)
                }
            } catch {
                NSLog("Najwa: transcription failed: \(error.localizedDescription)")
            }
        }
    }
}
