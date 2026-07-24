import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var controller: DictationController!
    private var hotkeys: HotkeyMonitor!
    private var statusMenuItem: NSMenuItem!
    private var fnStatusItem: NSMenuItem!
    private var modelStatusItem: NSMenuItem!
    private var latencyItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setStatusGlyph()

        let menu = NSMenu()
        statusMenuItem = NSMenuItem(title: "Najwa — idle", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        fnStatusItem = NSMenuItem(title: "key: starting…", action: nil, keyEquivalent: "")
        fnStatusItem.isEnabled = false
        menu.addItem(fnStatusItem)
        modelStatusItem = NSMenuItem(title: "model: loading…", action: nil, keyEquivalent: "")
        modelStatusItem.isEnabled = false
        menu.addItem(modelStatusItem)
        latencyItem = NSMenuItem(title: "last: —", action: nil, keyEquivalent: "")
        latencyItem.isEnabled = false
        menu.addItem(latencyItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Najwa", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu

        controller = DictationController()
        controller.onStateChange = { [weak self] state in
            DispatchQueue.main.async { self?.render(state) }
        }
        controller.onModelStatus = { [weak self] msg in
            DispatchQueue.main.async { self?.modelStatusItem?.title = "model: \(msg)" }
        }
        controller.onLatency = { [weak self] seconds in
            DispatchQueue.main.async {
                self?.latencyItem?.title = String(format: "last: %.0f ms", seconds * 1000)
            }
        }

        hotkeys = HotkeyMonitor(
            onBegin: { [weak self] in self?.controller.beginRecording() },
            onEnd:   { [weak self] in self?.controller.endRecording() }
        )
        hotkeys.onStatus = { [weak self] _, msg in
            DispatchQueue.main.async { self?.fnStatusItem?.title = "key: \(msg)" }
        }
        // Accessibility powers both the fn event tap and text injection.
        Permissions.requestAccessibilityIfNeeded()
        hotkeys.start()
    }

    private func render(_ state: DictationController.State) {
        switch state {
        case .idle:      statusMenuItem.title = "Najwa — idle"
        case .recording: statusMenuItem.title = "Najwa — listening…"
        case .working:   statusMenuItem.title = "Najwa — transcribing…"
        }
    }

    // The nūn (ن) mark as the menu-bar glyph until vector assets are added.
    // Always white, in every state (commit 656ddd0); the HUD is the recording cue.
    private func setStatusGlyph() {
        guard let button = statusItem.button else { return }
        let attr = NSAttributedString(
            string: "ن",
            attributes: [
                .font: NSFont.systemFont(ofSize: 16, weight: .medium),
                .foregroundColor: NSColor.white
            ]
        )
        button.attributedTitle = attr
        button.image = nil
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
