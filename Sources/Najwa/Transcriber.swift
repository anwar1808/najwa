import Foundation

/// Speech-to-text abstraction. The app depends only on this protocol, so the
/// engine (currently WhisperKit; a Parakeet CoreML port later) is a drop-in.
protocol Transcriber {
    /// Transcribe mono float samples held entirely in memory.
    func transcribe(_ samples: [Float], sampleRate: Double) async throws -> String
}
