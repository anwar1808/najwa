import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var controller: DictationController!
    private var hotkeys: HotkeyMonitor!
    private var statusMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setStatusGlyph(recording: false)

        let menu = NSMenu()
        statusMenuItem = NSMenuItem(title: "Najwa — idle", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Hold fn to dictate · double-tap fn to lock",
                                action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Najwa", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu

        controller = DictationController()
        controller.onStateChange = { [weak self] state in
            DispatchQueue.main.async { self?.render(state) }
        }

        hotkeys = HotkeyMonitor(
            onBegin: { [weak self] in self?.controller.beginRecording() },
            onEnd:   { [weak self] in self?.controller.endRecording() }
        )
        hotkeys.start()

        // Surface permission state on launch so the user knows what to grant.
        Permissions.requestAccessibilityIfNeeded()
    }

    private func render(_ state: DictationController.State) {
        switch state {
        case .idle:
            setStatusGlyph(recording: false)
            statusMenuItem.title = "Najwa — idle"
        case .recording:
            setStatusGlyph(recording: true)
            statusMenuItem.title = "Najwa — listening…"
        case .working:
            setStatusGlyph(recording: false)
            statusMenuItem.title = "Najwa — transcribing…"
        }
    }

    // The nūn (ن) mark as the menu-bar glyph until vector assets are added.
    private func setStatusGlyph(recording: Bool) {
        guard let button = statusItem.button else { return }
        let color: NSColor = recording ? .systemRed : .labelColor
        let attr = NSAttributedString(
            string: "ن",
            attributes: [
                .font: NSFont.systemFont(ofSize: 16, weight: .medium),
                .foregroundColor: color
            ]
        )
        button.attributedTitle = attr
        button.image = nil
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
