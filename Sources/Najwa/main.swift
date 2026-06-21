import AppKit

// Najwa — local, privacy-first voice dictation for macOS.
// Status-bar agent app (no Dock icon, no main window).

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu-bar agent; never steals focus
app.run()
