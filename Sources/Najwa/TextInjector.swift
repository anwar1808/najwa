import AppKit
import CoreGraphics

/// Injects text at the cursor of whatever app currently has focus, using
/// CGEvent Unicode synthesis. Requires Accessibility permission.
struct TextInjector {
    func inject(_ text: String) {
        guard !text.isEmpty else { return }
        guard AXIsProcessTrusted() else {
            NSLog("Najwa: cannot inject — Accessibility not granted.")
            return
        }

        let source = CGEventSource(stateID: .combinedSessionState)
        // Type in chunks: CGEvent Unicode strings are bounded in length.
        let scalars = Array(text.utf16)
        let chunkSize = 20
        var index = 0
        while index < scalars.count {
            let end = min(index + chunkSize, scalars.count)
            var slice = Array(scalars[index..<end])

            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else { break }

            down.keyboardSetUnicodeString(stringLength: slice.count, unicodeString: &slice)
            up.keyboardSetUnicodeString(stringLength: slice.count, unicodeString: &slice)
            down.post(tap: .cgAnnotatedSessionEventTap)
            up.post(tap: .cgAnnotatedSessionEventTap)

            index = end
            usleep(1500) // small gap so fast apps don't drop characters
        }
    }
}
