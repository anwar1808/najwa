import AVFoundation

/// Captures microphone audio entirely in memory. Nothing is ever written to disk.
///
/// - Voice processing (system noise suppression / AEC) is enabled on the input
///   node, which is the programmatic counterpart to the Control-Centre
///   "Voice Isolation" mic mode.
/// - On stop, the in-memory float buffer is gain-normalised ("isolate, then
///   amplify") so a genuine whisper becomes readable, then handed off and freed.
final class AudioCapture {
    private let engine = AVAudioEngine()
    private var samples: [Float] = []
    private let lock = NSLock()
    private var sampleRate: Double = 16_000
    private var capturing = false

    /// Called on the main thread with a 0…1 level for the waveform HUD.
    var onLevel: ((Float) -> Void)?

    private var voiceProcessingReady = false

    init() {
        // Prewarm at launch so the first recording starts instantly. Enabling
        // voice processing the first time is slow; doing it here keeps it off the
        // hot path. (It may no-op until mic permission is granted, then retries.)
        configureVoiceProcessing()
        engine.prepare()
    }

    private func configureVoiceProcessing() {
        guard !voiceProcessingReady else { return }
        do {
            try engine.inputNode.setVoiceProcessingEnabled(true) // noise suppression + AEC
            voiceProcessingReady = true
        } catch {
            NSLog("Najwa: voice processing not enabled yet: \(error.localizedDescription)")
        }
    }

    func start() {
        guard !capturing else { return }
        configureVoiceProcessing() // retry if mic permission arrived after launch
        samples.removeAll(keepingCapacity: true)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        sampleRate = format.sampleRate

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.accumulate(buffer)
        }

        do {
            try engine.start()
            capturing = true
        } catch {
            NSLog("Najwa: failed to start audio engine: \(error.localizedDescription)")
            input.removeTap(onBus: 0)
        }
    }

    /// Stops capture and returns the normalised mono buffer (in memory only).
    @discardableResult
    func stop() -> (samples: [Float], sampleRate: Double) {
        guard capturing else { return ([], sampleRate) }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        capturing = false

        lock.lock()
        var out = samples
        samples.removeAll(keepingCapacity: false) // free the audio immediately
        lock.unlock()

        normalizeGain(&out)
        return (out, sampleRate)
    }

    private func accumulate(_ buffer: AVAudioPCMBuffer) {
        guard let ch = buffer.floatChannelData else { return }
        let n = Int(buffer.frameLength)
        let mono = ch[0]

        // RMS level for the HUD.
        var sum: Float = 0
        for i in 0..<n { sum += mono[i] * mono[i] }
        let rms = n > 0 ? (sum / Float(n)).squareRoot() : 0
        let level = min(1, rms * 6) // gentle scaling so whispers still register
        DispatchQueue.main.async { [weak self] in self?.onLevel?(level) }

        lock.lock()
        samples.append(contentsOf: UnsafeBufferPointer(start: mono, count: n))
        lock.unlock()
    }

    /// Peak-normalise toward a target so quiet/whispered input is usable.
    private func normalizeGain(_ buf: inout [Float]) {
        var peak: Float = 0
        for s in buf { peak = max(peak, abs(s)) }
        guard peak > 0.0001 else { return }
        let target: Float = 0.95
        let gain = min(target / peak, 12) // cap gain so silence isn't blown up
        if gain > 1 {
            for i in buf.indices { buf[i] *= gain }
        }
    }
}
