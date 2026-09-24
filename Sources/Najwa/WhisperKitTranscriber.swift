import Foundation
import AVFoundation
import WhisperKit

/// On-device speech-to-text via WhisperKit (CoreML Whisper). The model is
/// downloaded once on first launch from Hugging Face, then runs fully offline.
/// Audio is resampled to 16 kHz mono in memory before inference.
final class WhisperKitTranscriber: Transcriber {
    private var kit: WhisperKit?
    private let modelName: String

    /// Human-readable load state, surfaced in the menu.
    var onStatus: ((String) -> Void)?

    /// Personal vocabulary (shared with Pensieve). Supplies Whisper's prompt
    /// and the post-decode correction pass; fully bypassed when switched off.
    private let vocabulary = Vocabulary.shared

    // Speed-tuned decode options: fix the language (skip detection), drop
    // timestamps, and VAD-chunk so long (locked-mode) dictations beyond 30s
    // still transcribe fully.
    private let baseDecodeOptions = DecodingOptions(
        task: .transcribe,
        language: "en",
        temperatureFallbackCount: 3,
        skipSpecialTokens: true,
        withoutTimestamps: true,
        wordTimestamps: false,
        // Hallucination guards: drop non-speech (rain, silence, fans) instead of
        // inventing words. Tightened for large-v3, which is slightly more prone to
        // confident non-speech hallucination than the turbo tier.
        compressionRatioThreshold: 2.4,   // kills repetitive hallucinated loops
        logProbThreshold: -0.7,           // drop more low-confidence guesses
        noSpeechThreshold: 0.45,          // flag non-speech segments more readily
        chunkingStrategy: .vad
    )

    /// Base options plus the vocabulary prompt, encoded with the loaded model's
    /// tokenizer. Prompt tokens are prepended after <|startofprev|>, the same
    /// way WhisperKit's CLI `--prompt` does it. Note WhisperKit skips its
    /// KV-prefill cache when prompt tokens are present, so this costs a little
    /// decode time — measured via `--selftest`, and gone when vocab is off.
    private func decodeOptions(for kit: WhisperKit) -> DecodingOptions {
        var opts = baseDecodeOptions
        guard let prompt = vocabulary.promptText, let tokenizer = kit.tokenizer else { return opts }
        let tokens = tokenizer.encode(text: " " + prompt).filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        guard !tokens.isEmpty else { return opts }
        opts.promptTokens = tokens
        opts.usePrefillPrompt = true
        // With prompt tokens WhisperKit skips its prefill cache, so its "first
        // token" check lands on the first FORCED prompt token, whose log-prob is
        // always low → the segment ends before a word is decoded (empty text
        // for every clip). The compression/log-prob fallbacks still apply.
        opts.firstTokenLogProbThreshold = nil
        // Diagnostic toggles for `--selftest` only (NAJWA_EXP=novad,ts,nothresh).
        let exp = ProcessInfo.processInfo.environment["NAJWA_EXP"] ?? ""
        if exp.contains("novad") { opts.chunkingStrategy = ChunkingStrategy.none }
        if exp.contains("ts") { opts.withoutTimestamps = false }
        if exp.contains("nothresh") { opts.compressionRatioThreshold = nil; opts.logProbThreshold = nil; opts.noSpeechThreshold = nil }
        return opts
    }

    /// Single source of truth for the model. Full large-v3 (latest checkpoint) —
    /// maximum accuracy; heavier decode than the turbo tier. Note the decode
    /// options above pin `language: "en"` for speed — change both together if
    /// non-English dictation is ever needed.
    init(model: String = "openai_whisper-large-v3-v20240930") {
        self.modelName = model
    }

    /// The bundled model lives under the app's own Application Support directory
    /// (NOT ~/Documents — that folder is TCC-protected, so a menu-bar app is
    /// denied read access there and the load silently fails). Application Support
    /// is un-gated: the app can always read its own subfolder without a prompt.
    static let modelsRoot: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Najwa/models", isDirectory: true)

    /// Loads the model, then warms the pipeline so the first real transcription
    /// isn't slow. Safe to call once at launch.
    ///
    /// IMPORTANT: we deliberately do NOT use WhisperKit's `prewarm: true`. Its
    /// prewarm step does an ANE model specialisation that *deadlocks* when Najwa
    /// runs as a menu-bar (LaunchServices) agent — the call never returns, so the
    /// model never becomes ready. That was the real cause of "model loading keeps
    /// failing": the app sat at "loading…" forever. Instead we load the models
    /// (no prewarm) and warm the ANE ourselves with one short silent buffer,
    /// which is safe in-process (verified transcribing in the menu-bar app).
    func prepare() async {
        onStatus?("loading model…")
        let localFolder = Self.modelsRoot.appendingPathComponent(modelName, isDirectory: true)
        let haveLocal = FileManager.default.fileExists(atPath: localFolder.path)
        do {
            // When the model is already on disk, point WhisperKit straight at it
            // (`modelFolder` + `download: false`): loads fully offline and never
            // touches Hugging Face, so a flaky network at launch can't fail the
            // load. First run only (no local copy) downloads once into the same
            // un-gated Application Support root. Never `prewarm` — see above.
            let config = haveLocal
                ? WhisperKitConfig(model: modelName, modelFolder: localFolder.path,
                                   prewarm: false, load: true, download: false)
                : WhisperKitConfig(model: modelName, downloadBase: Self.modelsRoot,
                                   prewarm: false, load: true, download: true)
            let k = try await WhisperKit(config)
            kit = k
            onStatus?("ready")
            NSLog("Najwa: WhisperKit model '\(modelName)' loaded (local=\(haveLocal)).")
            // Warm the ANE off the hot path with a short silent buffer so the
            // first real dictation is fast — the safe stand-in for `prewarm`.
            vocabulary.reloadIfChanged()
            _ = try? await k.transcribe(audioArray: [Float](repeating: 0, count: 16_000),
                                        decodeOptions: decodeOptions(for: k))
        } catch {
            onStatus?("model load failed")
            NSLog("Najwa: WhisperKit load failed: \(error.localizedDescription)")
        }
    }

    func transcribe(_ samples: [Float], sampleRate: Double) async throws -> String {
        guard let kit else { return "[Najwa: model still loading — try again in a moment]" }
        guard !samples.isEmpty else { return "" }

        let t0 = ProcessInfo.processInfo.systemUptime
        let audio = AudioResampler.to16kMono(samples, from: sampleRate)
        vocabulary.reloadIfChanged() // a stat() call; picks up edits made in Pensieve
        let results = try await kit.transcribe(audioArray: audio, decodeOptions: decodeOptions(for: kit))
        let decoded = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let dt = ProcessInfo.processInfo.systemUptime - t0
        NSLog(String(format: "Najwa: ASR %.0fms for %.1fs audio", dt * 1000, Double(audio.count) / 16_000))
        if Self.isNonSpeechArtifact(decoded) {
            // Log length only, never content: nothing dictated is written to disk.
            NSLog("Najwa: dropped as non-speech artifact (\(decoded.count) chars)")
            return ""
        }
        if vocabulary.isPromptEcho(decoded) {
            NSLog("Najwa: dropped as vocabulary-prompt echo (\(decoded.count) chars)")
            return ""
        }
        return vocabulary.apply(to: decoded)
    }

    /// Whisper emits a small, well-known set of single-token "hallucinations" on
    /// non-speech audio (e.g. "so", "you", "the", "thank you"). Drop the result
    /// only when the ENTIRE output is one of these — real dictation never is.
    private static let artifacts: Set<String> = [
        "so", "you", "the", "thanks", "thank you", "thanks for watching",
        "thank you for watching", "bye", "uh", "um", "okay.", "you.",
    ]
    private static func isNonSpeechArtifact(_ text: String) -> Bool {
        let key = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,!?…"))
        return key.isEmpty || artifacts.contains(key)
    }
}

/// Resamples mono Float audio to 16 kHz using AVAudioConverter. In-memory only.
enum AudioResampler {
    static func to16kMono(_ input: [Float], from sourceRate: Double, to targetRate: Double = 16_000) -> [Float] {
        guard sourceRate > 0, abs(sourceRate - targetRate) > 1 else { return input }
        guard
            let inFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sourceRate, channels: 1, interleaved: false),
            let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: targetRate, channels: 1, interleaved: false),
            let converter = AVAudioConverter(from: inFormat, to: outFormat),
            let inBuffer = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: AVAudioFrameCount(input.count))
        else { return input }

        inBuffer.frameLength = AVAudioFrameCount(input.count)
        if let dst = inBuffer.floatChannelData {
            input.withUnsafeBufferPointer { src in
                dst[0].update(from: src.baseAddress!, count: input.count)
            }
        }

        let ratio = targetRate / sourceRate
        let capacity = AVAudioFrameCount(Double(input.count) * ratio) + 4096
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return input }

        var supplied = false
        var convError: NSError?
        converter.convert(to: outBuffer, error: &convError) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true
            status.pointee = .haveData
            return inBuffer
        }
        if let convError { NSLog("Najwa: resample error: \(convError.localizedDescription)") }

        let n = Int(outBuffer.frameLength)
        guard n > 0, let ch = outBuffer.floatChannelData else { return input }
        return Array(UnsafeBufferPointer(start: ch[0], count: n))
    }
}
