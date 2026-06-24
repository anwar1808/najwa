import AppKit
import AVFoundation
import ApplicationServices

enum Permissions {
    /// Prompts (once) for Accessibility, required for the fn event tap and text injection.
    static func requestAccessibilityIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted {
            NSLog("Najwa: Accessibility not yet granted. Add Najwa under System Settings → Privacy & Security → Accessibility.")
        }
    }

    static var accessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Requests microphone access; the system shows the prompt on first capture.
    static func requestMicrophone(_ completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        default:
            completion(false)
        }
    }
}
