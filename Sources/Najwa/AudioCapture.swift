import AVFoundation
import Accelerate

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

    // No work at init. Do NOT call `engine.prepare()` here: at app launch the
    // microphone permission hasn't been requested yet (that happens on the first
    // `beginRecording()`), so AVAudioEngine has no usable I/O node and prepare()
    // throws `inputNode != nullptr || outputNode != nullptr`. That NSException
    // used to abort DictationController construction, which is why the WhisperKit
    // model load was never scheduled and the menu sat at "loading…" forever. The
    // engine graph is built lazily in `start()`, after permission is granted.

    /// Voice processing (noise suppression + AEC, the counterpart to Control
    /// Centre's "Voice Isolation") is toggled ONLY around a live capture — see
    /// `start()`/`stop()`. It must never be left on while idle: an active
    /// voice-processing IO unit puts the whole system into communication mode and
    /// **ducks all system output audio** for as long as it lives. Leaving it on
    /// at launch quietly halved the Mac's audible volume the entire time Najwa
    /// ran. `setVoiceProcessingEnabled` must be called with the engine stopped.
    private func setVoiceProcessing(_ on: Bool) {
        do {
            try engine.inputNode.setVoiceProcessingEnabled(on)
        } catch {
            NSLog("Najwa: could not \(on ? "enable" : "disable") voice processing: \(error.localizedDescription)")
        }
    }

    func start() {
        guard !capturing else { return }
        setVoiceProcessing(true) // engage isolation just for this capture
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        samples.reserveCapacity(48_000 * 30) // ~30s @ 48kHz, avoids growth churn
        lock.unlock()

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
        setVoiceProcessing(false) // release the system-wide output ducking while idle

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
        var rms: Float = 0
        if n > 0 { vDSP_rmsqv(mono, 1, &rms, vDSP_Length(n)) }
        let level = min(1, rms * 6) // gentle scaling so whispers still register
        DispatchQueue.main.async { [weak self] in self?.onLevel?(level) }

        lock.lock()
        samples.append(contentsOf: UnsafeBufferPointer(start: mono, count: n))
        lock.unlock()
    }

    /// Peak-normalise toward a target so quiet/whispered input is usable.
    private func normalizeGain(_ buf: inout [Float]) {
        guard !buf.isEmpty else { return }
        var peak: Float = 0
        vDSP_maxmgv(buf, 1, &peak, vDSP_Length(buf.count))
        guard peak > 0.0001 else { return }
        let target: Float = 0.95
        var gain = min(target / peak, 12) // cap gain so silence isn't blown up
        if gain > 1 {
            vDSP_vsmul(buf, 1, &gain, &buf, 1, vDSP_Length(buf.count))
        }
    }
}
