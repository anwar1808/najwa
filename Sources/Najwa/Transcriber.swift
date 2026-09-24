import Foundation

/// Speech-to-text abstraction. The app depends only on this protocol, so the
/// engine (currently WhisperKit; a Parakeet CoreML port later) is a drop-in.
protocol Transcriber: AnyObject {
    /// Human-readable load state, surfaced in the menu.
    var onStatus: ((String) -> Void)? { get set }

    /// Loads (and on first run downloads) the model; safe to call once at launch.
    func prepare() async

    /// Transcribe mono float samples held entirely in memory.
    func transcribe(_ samples: [Float], sampleRate: Double) async throws -> String
}
