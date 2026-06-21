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

    init(model: String = "small") {
        self.modelName = model
    }

    /// Loads (and on first run downloads) the model. Safe to call once at launch.
    func prepare() async {
        onStatus?("downloading \(modelName) model…")
        do {
            let config = WhisperKitConfig(model: modelName)
            kit = try await WhisperKit(config)
            onStatus?("\(modelName) ready")
            NSLog("Najwa: WhisperKit model '\(modelName)' loaded.")
        } catch {
            onStatus?("model load failed")
            NSLog("Najwa: WhisperKit load failed: \(error.localizedDescription)")
        }
    }

    func transcribe(_ samples: [Float], sampleRate: Double) async throws -> String {
        guard let kit else { return "[Najwa: model still loading — try again in a moment]" }
        guard !samples.isEmpty else { return "" }

        let audio = AudioResampler.to16kMono(samples, from: sampleRate)
        let results = try await kit.transcribe(audioArray: audio)
        let text = results.map { $0.text }.joined(separator: " ")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
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
