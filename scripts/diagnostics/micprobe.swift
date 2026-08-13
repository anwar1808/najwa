import AVFoundation
import Accelerate

// Mimics Najwa's AudioCapture: AVAudioEngine input tap, optional voice processing.
// Records ~2s and prints peak/RMS so we can tell live audio from silence.

let useVP = CommandLine.arguments.contains("--vp")
let engine = AVAudioEngine()

let sem = DispatchSemaphore(value: 0)
var granted = false
switch AVCaptureDevice.authorizationStatus(for: .audio) {
case .authorized: granted = true; sem.signal()
case .notDetermined:
    AVCaptureDevice.requestAccess(for: .audio) { ok in granted = ok; sem.signal() }
default: sem.signal()
}
sem.wait()
guard granted else { print("MIC-PERMISSION-DENIED"); exit(2) }

if useVP {
    do { try engine.inputNode.setVoiceProcessingEnabled(true) }
    catch { print("VP-ENABLE-FAILED: \(error.localizedDescription)") }
}

let input = engine.inputNode
let format = input.outputFormat(forBus: 0)
print("format: \(format.sampleRate) Hz, \(format.channelCount) ch, vp=\(useVP)")

var samples: [Float] = []
let lock = NSLock()
input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
    guard let ch = buffer.floatChannelData else { return }
    let n = Int(buffer.frameLength)
    lock.lock()
    samples.append(contentsOf: UnsafeBufferPointer(start: ch[0], count: n))
    lock.unlock()
}

do { try engine.start() } catch {
    print("ENGINE-START-FAILED: \(error.localizedDescription)")
    exit(3)
}

Thread.sleep(forTimeInterval: 2.0)
input.removeTap(onBus: 0)
engine.stop()

lock.lock()
let buf = samples
lock.unlock()

var peak: Float = 0, rms: Float = 0
if !buf.isEmpty {
    vDSP_maxmgv(buf, 1, &peak, vDSP_Length(buf.count))
    vDSP_rmsqv(buf, 1, &rms, vDSP_Length(buf.count))
}
print(String(format: "samples=%d peak=%.6f rms=%.6f -> %@",
             buf.count, peak, rms,
             buf.isEmpty ? "NO-DATA" : (peak < 0.0001 ? "SILENCE" : "LIVE-AUDIO")))
