import Foundation
import CoreGraphics

/// Detects the **fn / Globe** key via a `CGEventTap` on `flagsChanged`, watching
/// the secondary-fn modifier bit (`CGEventFlags.maskSecondaryFn`, 0x800000).
///
/// We tried the IOKit HID layer first (IOHIDManager on the Apple Top Case device,
/// vendor usage 0xff00/0x03) — but on current hardware/macOS the fn key delivers
/// *nothing* through that device, while a CGEventTap reports it cleanly
/// (keycode 63, flags 0x800100 down / 0x100 up). The event tap also needs only
/// Accessibility, not Input Monitoring. To stop macOS acting on fn itself, set the
/// Globe key to "Do Nothing" in System Settings → Keyboard.
///
/// Emits two semantic events — begin and end — via a hold / double-tap state machine:
///   key down             -> begin immediately
///   release > holdMin     -> end (hold-to-talk)
///   quick tap             -> wait tapWindow; second tap => LOCKED, else end
///   in LOCKED, double-tap -> end
final class HotkeyMonitor {
    private let onBegin: () -> Void
    private let onEnd: () -> Void

    /// (active, humanReadableStatus) — surfaced in the menu.
    var onStatus: ((Bool, String) -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var accessPoll: DispatchSourceTimer?

    /// Tracks the fn-bit state so we only fire on transitions (other modifiers
    /// also produce flagsChanged events, and they carry the fn bit while fn is held).
    private var fnIsDown = false

    private let holdMin: TimeInterval = 0.25
    private let tapWindow: TimeInterval = 0.25

    private enum Mode { case idle, holding, tapPending, locked, stopArming }
    private var mode: Mode = .idle
    private var keyDownTime: TimeInterval = 0
    private var pendingWork: DispatchWorkItem?

    init(onBegin: @escaping () -> Void, onEnd: @escaping () -> Void) {
        self.onBegin = onBegin
        self.onEnd = onEnd
    }

    func start() {
        // A CGEventTap requires Accessibility. AXIsProcessTrusted() is the real gate;
        // tapCreate also returns nil if it isn't granted.
        guard Permissions.accessibilityTrusted else {
            report(false, "off — enable Accessibility, then quit & reopen Najwa")
            NSLog("Najwa: Accessibility not granted; fn tap cannot start.")
            pollForAccess()
            return
        }
        installTap()
    }

    private func installTap() {
        guard tap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, ctx in
            guard let ctx = ctx else { return Unmanaged.passUnretained(event) }
            Unmanaged<HotkeyMonitor>.fromOpaque(ctx).takeUnretainedValue().handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                        place: .headInsertEventTap,
                                        options: .listenOnly,
                                        eventsOfInterest: mask,
                                        callback: callback,
                                        userInfo: ctx) else {
            report(false, "off — enable Accessibility, then quit & reopen Najwa")
            NSLog("Najwa: CGEvent.tapCreate failed (Accessibility?).")
            pollForAccess()
            return
        }
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, CFRunLoopMode.commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        tap = t
        runLoopSource = src
        report(true, "ready (fn)")
        NSLog("Najwa: fn event tap armed.")
    }

    /// If the tap couldn't start (Accessibility missing), watch for the grant and
    /// self-arm without a relaunch.
    private func pollForAccess() {
        accessPoll?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if Permissions.accessibilityTrusted {
                self.accessPoll?.cancel()
                self.accessPoll = nil
                self.installTap()
            }
        }
        accessPoll = timer
        timer.resume()
    }

    func stop() {
        pendingWork?.cancel()
        accessPoll?.cancel()
        accessPoll = nil
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, CFRunLoopMode.commonModes)
        }
        runLoopSource = nil
        tap = nil
    }

    private func report(_ active: Bool, _ msg: String) {
        DispatchQueue.main.async { [weak self] in self?.onStatus?(active, msg) }
    }

    /// Called from the event-tap run-loop source (main thread) for each flagsChanged.
    private func handle(type: CGEventType, event: CGEvent) {
        // The system can disable a tap after a timeout / heavy input; re-enable it.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return
        }
        let fnDown = event.flags.contains(.maskSecondaryFn)
        guard fnDown != fnIsDown else { return }   // only act on fn transitions
        fnIsDown = fnDown
        if fnDown { fnPressed() } else { fnReleased() }
    }

    private func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }

    private func fnPressed() {
        switch mode {
        case .idle:
            keyDownTime = now()
            mode = .holding
            onBegin()
        case .tapPending:
            pendingWork?.cancel()
            mode = .locked            // second tap → lock on (already recording)
        case .locked:
            keyDownTime = now()
            mode = .stopArming
        case .stopArming:
            pendingWork?.cancel()
            mode = .idle              // confirming double-tap → stop
            onEnd()
        case .holding:
            break
        }
    }

    private func fnReleased() {
        switch mode {
        case .holding:
            if now() - keyDownTime > holdMin {
                mode = .idle
                onEnd()               // hold-to-talk finished
            } else {
                mode = .tapPending
                schedule(after: tapWindow) { [weak self] in
                    guard let self, self.mode == .tapPending else { return }
                    self.mode = .idle
                    self.onEnd()      // short single-tap dictation
                }
            }
        case .stopArming:
            schedule(after: tapWindow) { [weak self] in
                guard let self, self.mode == .stopArming else { return }
                self.mode = .locked   // stray tap; stay locked
            }
        default:
            break
        }
    }

    private func schedule(after: TimeInterval, _ block: @escaping () -> Void) {
        pendingWork?.cancel()
        let work = DispatchWorkItem(block: block)
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + after, execute: work)
    }
}
