import AppKit
import CoreGraphics

// Replicates Najwa's TextInjector byte-for-byte.
let text = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "INJECTION-TEST"
print("AXIsProcessTrusted: \(AXIsProcessTrusted())")

let source = CGEventSource(stateID: .combinedSessionState)
let scalars = Array(text.utf16)
let chunkSize = 20
var index = 0
while index < scalars.count {
    let end = min(index + chunkSize, scalars.count)
    var slice = Array(scalars[index..<end])
    guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
          let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
    else { print("EVENT-CREATE-FAILED"); break }
    down.keyboardSetUnicodeString(stringLength: slice.count, unicodeString: &slice)
    up.keyboardSetUnicodeString(stringLength: slice.count, unicodeString: &slice)
    down.post(tap: .cgAnnotatedSessionEventTap)
    up.post(tap: .cgAnnotatedSessionEventTap)
    index = end
    usleep(1500)
}
print("posted \(scalars.count) utf16 units")
