import AppKit

/// Bottom-centre floating pill with a live, voice-reactive waveform.
/// CRITICAL: it must never steal focus, or text injection breaks. So it is a
/// non-activating panel, click-through, at a floating level, on all Spaces.
final class HUDController {
    private let panel: NSPanel
    private let waveform: WaveformView
    private let working: WorkingView

    init() {
        let size = NSSize(width: 200, height: 30)
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
        blur.layer?.cornerRadius = 15
        blur.layer?.masksToBounds = true

        waveform = WaveformView(frame: blur.bounds)
        waveform.autoresizingMask = [.width, .height]
        blur.addSubview(waveform)
        // The "working" state lives in the same pill, cross-faded over the wave,
        // so release → transcribe → inject reads as one object changing state
        // rather than the HUD vanishing and something else appearing.
        working = WorkingView(frame: blur.bounds)
        working.autoresizingMask = [.width, .height]
        working.alphaValue = 0
        blur.addSubview(working)
        panel.contentView = blur
    }

    func show() {
        reposition()
        panel.alphaValue = 0
        working.alphaValue = 0
        waveform.alphaValue = 1
        panel.orderFrontRegardless()
        waveform.startAnimating()
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
            self?.waveform.stopAnimating()
            self?.working.stop()
        })
    }

    func update(level: Float) {
        waveform.push(level)
    }

    // MARK: - Working state (release → text landed)

    /// The wave settles into the breathing nūn (ن) — the same glyph, font and
    /// colour as the menu-bar icon — until the text has landed.
    func beginWorking() {
        waveform.push(0)
        working.start()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            waveform.animator().alphaValue = 0
            working.animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            self?.waveform.stopAnimating()
        })
    }

    /// Text has landed (or nothing will): fade the pill away.
    func finish() {
        hide()
    }

    /// Transient text pill (same spot as the waveform) for feedback that must
    /// never be silent — e.g. "heard nothing" when a dictation transcribes to
    /// empty instead of quietly injecting nothing. Non-activating/click-through
    /// like the main panel, so it can never steal focus either.
    private var flashPanel: NSPanel?
    func flash(_ message: String, duration: TimeInterval = 1.6) {
        flashPanel?.orderOut(nil) // replace any previous flash immediately

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = NSColor.white.withAlphaComponent(0.95)
        label.sizeToFit()

        let size = NSSize(width: label.frame.width + 28, height: 28)
        let p = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .floating
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        p.hidesOnDeactivate = false

        let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 14
        blur.layer?.masksToBounds = true
        label.setFrameOrigin(NSPoint(x: (size.width - label.frame.width) / 2,
                                     y: (size.height - label.frame.height) / 2))
        blur.addSubview(label)
        p.contentView = blur

        if let screen = NSScreen.main {
            let f = screen.frame
            p.setFrameOrigin(NSPoint(x: f.midX - size.width / 2, y: f.minY + 6))
        }

        flashPanel = p
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            p.animator().alphaValue = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self, weak p] in
            guard let p, self?.flashPanel === p else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                p.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                p.orderOut(nil)
                if self?.flashPanel === p { self?.flashPanel = nil }
            })
        }
    }

    private func reposition() {
        guard let screen = NSScreen.main else { return }
        let f = screen.frame                 // full screen, so we can hug the real bottom edge
        let w = panel.frame.width
        let x = f.midX - w / 2
        let y = f.minY + 6                    // ~6px above the very bottom of the screen
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

/// The nūn (ن), breathing while Najwa transcribes and types. Drawn with the
/// exact attributes of the menu-bar glyph (system font, medium, white) so the
/// pill and the menu bar read as one mark. Whole letter breathes: opacity
/// 0.55…1.0 and scale 0.92…1.06, one breath ≈ 1.3 s.
final class WorkingView: NSView {
    private var timer: Timer?
    private var t: CGFloat = 0   // breath phase

    /// Matches AppDelegate.setStatusGlyph (16 pt there; a touch larger here
    /// because the pill is roomier than the menu bar).
    private static let glyph = "ن"
    private static let font = NSFont.systemFont(ofSize: 18, weight: .medium)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    func start() {
        t = 0
        timer?.invalidate()
        let tm = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(tm, forMode: .common)
        timer = tm
        needsDisplay = true
    }

    func stop() {
        timer?.invalidate(); timer = nil
        t = 0
        needsDisplay = true
    }

    private func tick() {
        t += (2 * .pi) / (30 * 1.3)
        if t > 2 * .pi { t -= 2 * .pi }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let breath = (1 + sin(t - .pi / 2)) / 2          // 0…1, starts at 0
        let alpha = 0.55 + 0.45 * breath
        let scale = 0.92 + 0.14 * breath

        let str = NSAttributedString(string: Self.glyph, attributes: [
            .font: Self.font,
            .foregroundColor: NSColor.white.withAlphaComponent(alpha),
        ])
        // Centre on the glyph's ink, not its line box: Arabic glyphs sit high
        // in the line box, so line-box centring looks visibly off in a 30 pt pill.
        let ink = str.boundingRect(with: .zero, options: [.usesLineFragmentOrigin, .usesDeviceMetrics])
        ctx.saveGState()
        ctx.translateBy(x: bounds.midX, y: bounds.midY)
        ctx.scaleBy(x: scale, y: scale)
        str.draw(at: NSPoint(x: -ink.midX, y: -ink.midY))
        ctx.restoreGState()
    }
}

/// Flowing, animated sine waveform whose amplitude tracks your voice.
/// A moving carrier wave (phase advances each frame), tapered at the edges, with
/// the amplitude smoothly following the mic level — so it reads as real sound
/// waves rather than discrete bars.
final class WaveformView: NSView {
    private var targetAmp: CGFloat = 0   // latest mic level (0…1)
    private var amp: CGFloat = 0         // smoothed amplitude actually drawn
    private var phase: CGFloat = 0       // animates the wave's motion
    private var timer: Timer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    func push(_ level: Float) {
        targetAmp = CGFloat(max(0, min(1, level)))
    }

    func startAnimating() {
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopAnimating() {
        timer?.invalidate(); timer = nil
        targetAmp = 0; amp = 0; phase = 0
        needsDisplay = true
    }

    private func tick() {
        amp += (targetAmp - amp) * 0.25  // smooth toward the latest level
        phase += 0.34                    // scroll the wave
        if phase > .pi * 2 { phase -= .pi * 2 }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let area = bounds.insetBy(dx: 16, dy: 4)
        let midY = area.midY
        let maxAmp = area.height / 2
        let cycles: CGFloat = 3.2
        let shown = max(0.07, amp)       // always a gentle living ripple

        let path = CGMutablePath()
        let step: CGFloat = 1.5
        var x: CGFloat = area.minX
        var first = true
        while x <= area.maxX {
            let t = (x - area.minX) / area.width           // 0…1 across width
            let taper = sin(.pi * t)                        // fade to 0 at edges
            let y = midY + maxAmp * shown * taper * sin(cycles * 2 * .pi * t - phase)
            if first { path.move(to: CGPoint(x: x, y: y)); first = false }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
            x += step
        }

        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.95).cgColor)
        ctx.setLineWidth(2.0)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.addPath(path)
        ctx.strokePath()
    }
}
