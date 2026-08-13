import CoreGraphics
import Foundation

// Posts a synthetic fn (Globe) hold: flagsChanged with maskSecondaryFn set,
// held for the duration given as arg 1 (seconds, default 3), then released.
let hold = CommandLine.arguments.count > 1 ? Double(CommandLine.arguments[1]) ?? 3 : 3

let src = CGEventSource(stateID: .hidSystemState)
guard let down = CGEvent(keyboardEventSource: src, virtualKey: 63, keyDown: true) else {
    print("EVENT-CREATE-FAILED"); exit(1)
}
down.type = .flagsChanged
down.flags = [.maskSecondaryFn]
down.post(tap: .cghidEventTap)
print("fn down posted")

Thread.sleep(forTimeInterval: hold)

guard let up = CGEvent(keyboardEventSource: src, virtualKey: 63, keyDown: false) else {
    print("EVENT-CREATE-FAILED"); exit(1)
}
up.type = .flagsChanged
up.flags = []
up.post(tap: .cghidEventTap)
print("fn up posted")
