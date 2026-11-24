import Foundation
import AVFoundation
import WhisperKit

/// Headless verification of the real ASR pipeline (model load + resample +
/// transcribe) on an audio file, without needing the mic or a GUI. Invoked via:
///   Najwa --selftest /path/to/audio.(aiff|wav|m4a)
/// Prints model-load time, ASR time, and the transcript, then exits.
enum SelfTest {
    static func run(path: String) {
        guard let (samples, sr) = loadFloats(URL(fileURLWithPath: path)) else {
            print("SELFTEST: could not read audio at \(path)")
            exit(1)
        }
        print(String(format: "SELFTEST: loaded %.2fs of audio @ %.0fHz", Double(samples.count) / sr, sr))
        // NAJWA_WKLOG=info|debug surfaces WhisperKit's own decode log (fallbacks, forced tokens).
        if let lvl = ProcessInfo.processInfo.environment["NAJWA_WKLOG"] {
            Logging.shared.logLevel = lvl == "debug" ? .debug : .info
        }

        let sem = DispatchSemaphore(value: 0)
        let tx = WhisperKitTranscriber()
        Task {
            let t0 = ProcessInfo.processInfo.systemUptime
            await tx.prepare()
            let loadMs = (ProcessInfo.processInfo.systemUptime - t0) * 1000
            print("SELFTEST: \(Vocabulary.shared.status)")
            do {
                let t1 = ProcessInfo.processInfo.systemUptime
                let text = try await tx.transcribe(samples, sampleRate: sr)
                let asrMs = (ProcessInfo.processInfo.systemUptime - t1) * 1000
                print(String(format: "SELFTEST: load=%.0fms  asr=%.0fms", loadMs, asrMs))
                print("SELFTEST: text = \"\(text)\"")
            } catch {
                print("SELFTEST: transcribe error: \(error)")
            }
            sem.signal()
        }
        sem.wait()
    }

    /// Runs only the vocabulary pass on a string — no model, no mic. Handy for
    /// checking that a new rule or a sound-alike match behaves as expected.
    static func vocabOnly(text: String) {
        let v = Vocabulary.shared
        v.reloadIfChanged(force: true)
        print("VOCABTEST: \(v.status) (\(v.path))")
        print("VOCABTEST: in  = \"\(text)\"")
        print("VOCABTEST: out = \"\(v.apply(to: text))\"")
        print("VOCABTEST: echo = \(v.isPromptEcho(text))")
    }

    /// Runs only the cleanup pass on a string, no ASR, no mic: what v0.3.2
    /// would have typed, what the model returns now, whether the faithfulness
    /// check accepts it, and what Najwa would type.
    static func cleanupOnly(text: String) {
        let sem = DispatchSemaphore(value: 0)
        Task {
            let c = Cleanup()
            let before = await c.legacyPolish(text)
            let t0 = ProcessInfo.processInfo.systemUptime
            let r = await c.polishDetailed(text)
            let ms = (ProcessInfo.processInfo.systemUptime - t0) * 1000
            print("CLEANTEST: in      = \"\(text)\"")
            print("CLEANTEST: v0.3.2  = \"\(before)\"")
            print("CLEANTEST: check on v0.3.2 output = \(Cleanup.unfaithfulReason(raw: text, cleaned: before).map { "REJECTED, \($0)" } ?? "passes")")
            print("CLEANTEST: model   = \(r.modelOutput.map { "\"\($0)\"" } ?? "(none)")")
            print("CLEANTEST: outcome = \(r.outcome)")
            print("CLEANTEST: typed   = \"\(r.text)\"")
            print(String(format: "CLEANTEST: cleanup = %.0fms", ms))
            sem.signal()
        }
        sem.wait()
    }

    private static func loadFloats(_ url: URL) -> ([Float], Double)? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let fmt = file.processingFormat
        guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(file.length)) else { return nil }
        do { try file.read(into: buf) } catch { return nil }
        guard let ch = buf.floatChannelData else { return nil }
        return (Array(UnsafeBufferPointer(start: ch[0], count: Int(buf.frameLength))), fmt.sampleRate)
    }
}
