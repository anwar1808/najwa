import AppKit

/// Bottom-centre floating pill with a live, voice-reactive waveform.
/// CRITICAL: it must never steal focus, or text injection breaks. So it is a
/// non-activating panel, click-through, at a floating level, on all Spaces.
final class HUDController {
    private let panel: NSPanel
    private let waveform: WaveformView

    init() {
        let size = NSSize(width: 220, height: 56)
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false

        let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 16
        blur.layer?.masksToBounds = true

        waveform = WaveformView(frame: blur.bounds)
        waveform.autoresizingMask = [.width, .height]
        blur.addSubview(waveform)
        panel.contentView = blur
    }

    func show() {
        reposition()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel.orderOut(nil)
            self?.waveform.reset()
        })
    }

    func update(level: Float) {
        waveform.push(level)
    }

    private func reposition() {
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        let w = panel.frame.width
        let x = vf.midX - w / 2
        let y = vf.minY + 80
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

/// Simple bar-style waveform driven by recent audio levels.
final class WaveformView: NSView {
    private var levels: [CGFloat]
    private let barCount = 21

    override init(frame: NSRect) {
        levels = Array(repeating: 0, count: barCount)
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    func push(_ level: Float) {
        levels.removeFirst()
        levels.append(CGFloat(max(0.03, min(1, level))))
        needsDisplay = true
    }

    func reset() {
        levels = Array(repeating: 0, count: barCount)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let inset: CGFloat = 18
        let area = bounds.insetBy(dx: inset, dy: 12)
        let gap: CGFloat = 3
        let barW = (area.width - gap * CGFloat(barCount - 1)) / CGFloat(barCount)
        let midY = area.midY

        ctx.setFillColor(NSColor.white.withAlphaComponent(0.92).cgColor)
        for (i, lv) in levels.enumerated() {
            let h = max(2, lv * area.height)
            let x = area.minX + CGFloat(i) * (barW + gap)
            let rect = CGRect(x: x, y: midY - h / 2, width: barW, height: h)
            let path = CGPath(roundedRect: rect, cornerWidth: barW / 2, cornerHeight: barW / 2, transform: nil)
            ctx.addPath(path); ctx.fillPath()
        }
    }
}
