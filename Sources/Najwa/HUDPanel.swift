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

    /// The wave settles into the pulsing nūn dot. `showFill` adds a thin
    /// progress line under the dot, fed by `setProgress` — only worth showing
    /// for long dictations, where Whisper reports real per-window progress.
    func beginWorking(showFill: Bool) {
        waveform.push(0)
        working.start(showFill: showFill)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            waveform.animator().alphaValue = 0
            working.animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            self?.waveform.stopAnimating()
        })
    }

    /// 0…1 fraction of the audio transcribed so far.
    func setProgress(_ fraction: Double) {
        working.setProgress(fraction)
    }

    /// Text has landed (or nothing will): fade the pill away.
    func finish() {
        working.setProgress(1)
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

/// The nūn dot, breathing while Najwa transcribes and types. The dot is the
/// brand's recording mark; the wave it replaces is the curve. With `showFill`
/// a thin line under the dot fills left→right with real transcription progress.
final class WorkingView: NSView {
    private var timer: Timer?
    private var t: CGFloat = 0            // pulse phase
    private var target: CGFloat = 0       // reported progress 0…1
    private var shownFill: CGFloat = 0    // smoothed fill actually drawn
    private var showFill = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    func start(showFill: Bool) {
        self.showFill = showFill
        target = 0; shownFill = 0; t = 0
        timer?.invalidate()
        let tm = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(tm, forMode: .common)
        timer = tm
        needsDisplay = true
    }

    func stop() {
        timer?.invalidate(); timer = nil
        target = 0; shownFill = 0; t = 0
        needsDisplay = true
    }

    func setProgress(_ fraction: Double) {
        target = CGFloat(max(0, min(1, fraction)))
    }

    private func tick() {
        t += (2 * .pi) / (30 * 1.3)               // one breath ≈ 1.3 s
        if t > 2 * .pi { t -= 2 * .pi }
        shownFill += (target - shownFill) * 0.15  // ease toward reported progress
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let c = CGPoint(x: bounds.midX, y: bounds.midY + (showFill ? 2 : 0))
        // Breath: radius 3.2…4.6 pt, alpha 0.55…1.0, in step.
        let breath = (1 + sin(t - .pi / 2)) / 2          // 0…1, starts at 0
        let r = 3.2 + 1.4 * breath
        let a = 0.55 + 0.45 * breath
        ctx.setFillColor(NSColor.white.withAlphaComponent(a).cgColor)
        ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        // Soft halo so the pulse reads at a glance.
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.10 * breath).cgColor)
        let hr = r + 4
        ctx.fillEllipse(in: CGRect(x: c.x - hr, y: c.y - hr, width: 2 * hr, height: 2 * hr))

        guard showFill else { return }
        let track = CGRect(x: bounds.minX + 40, y: bounds.minY + 6, width: bounds.width - 80, height: 2)
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.18).cgColor)
        ctx.fill(track)
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        ctx.fill(CGRect(x: track.minX, y: track.minY, width: track.width * shownFill, height: track.height))
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
