import Foundation

/// Speech-to-text abstraction. Phase 2 swaps the stub for an on-device engine
/// (WhisperKit first as the known-good baseline, then the Parakeet CoreML port).
/// The rest of the app depends only on this protocol, so the model is a drop-in.
protocol Transcriber {
    /// Transcribe mono float samples held entirely in memory.
    func transcribe(_ samples: [Float], sampleRate: Double) async throws -> String
}

/// Placeholder used in the Phase-1 skeleton. It does NOT recognise speech — it
/// injects a clearly-marked sentinel so the end-to-end loop (hotkey → capture →
/// HUD → inject → history) can be exercised and permissions granted without
/// pretending dictation works yet.
struct StubTranscriber: Transcriber {
    func transcribe(_ samples: [Float], sampleRate: Double) async throws -> String {
        let seconds = sampleRate > 0 ? Double(samples.count) / sampleRate : 0
        return String(format: "[Najwa: ASR not wired yet — captured %.1fs of audio]", seconds)
    }
}
