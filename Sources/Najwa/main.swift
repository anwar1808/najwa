import AppKit

// Najwa — local, privacy-first voice dictation for macOS.
// Status-bar agent app (no Dock icon, no main window).

// Headless self-test: `Najwa --selftest <audiofile>` verifies the ASR pipeline.
// Add `--no-vocab` to run it with vocabulary correction off (A/B latency).
// `Najwa --vocabtest "some text"` runs only the post-decode correction pass.
let args = CommandLine.arguments
if args.contains("--no-vocab") {
    // Process-local override: does not touch the saved preference.
    UserDefaults.standard.setVolatileDomain([Vocabulary.enabledKey: false], forName: UserDefaults.argumentDomain)
}
if let i = args.firstIndex(of: "--vocabtest"), i + 1 < args.count {
    SelfTest.vocabOnly(text: args[i + 1])
    exit(0)
}
if let i = args.firstIndex(of: "--selftest"), i + 1 < args.count {
    SelfTest.run(path: args[i + 1])
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu-bar agent; never steals focus
app.run()
