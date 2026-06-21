import AppKit

// Najwa — local, privacy-first voice dictation for macOS.
// Status-bar agent app (no Dock icon, no main window).

// Headless self-test: `Najwa --selftest <audiofile>` verifies the ASR pipeline.
let args = CommandLine.arguments
if let i = args.firstIndex(of: "--selftest"), i + 1 < args.count {
    SelfTest.run(path: args[i + 1])
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu-bar agent; never steals focus
app.run()
