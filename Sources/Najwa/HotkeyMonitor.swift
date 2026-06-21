import AppKit
import CoreGraphics

/// Watches the `fn` (Globe) key via a CGEventTap and turns raw key transitions
/// into two semantic events: begin-recording and end-recording.
///
/// Robustness:
///  - If Accessibility isn't granted yet at launch, tap creation fails; we retry
///    on a timer, so granting it later engages `fn` WITHOUT a relaunch.
///  - macOS disables a tap that misbehaves or after certain events; we re-enable
///    it when we receive a tapDisabled notification, so `fn` doesn't silently die.
///
/// State machine (one key serves both modes):
///   idle      --fn down-->            holding   (onBegin immediately)
///   holding   --release > holdMin-->  idle      (onEnd: hold dictation)
///   holding   --release <= holdMin--> tapPending
///   tapPending --fn down (2nd tap)--> locked    (keep recording, hands-free)
///   tapPending --window elapses-->    idle      (onEnd: short dictation)
///   locked    --fn down (1st tap)-->  stopArming
///   stopArming --fn down (2nd tap)--> idle      (onEnd: stop locked session)
///   stopArming --window elapses-->    locked    (stray tap; stay recording)
final class HotkeyMonitor {
    private let onBegin: () -> Void
    private let onEnd: () -> Void

    /// (active, humanReadableStatus) — surfaced in the menu so state is visible.
    var onStatus: ((Bool, String) -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retryTimer: Timer?

    private let holdMin: TimeInterval = 0.25
    private let tapWindow: TimeInterval = 0.25

    private enum Mode { case idle, holding, tapPending, locked, stopArming }
    private var mode: Mode = .idle
    private var keyDownTime: TimeInterval = 0
    private var pendingWork: DispatchWorkItem?
    private var holdWatchdog: Timer?
    private var lastFnDown = false   // tracks fn edges so we consume only fn

    init(onBegin: @escaping () -> Void, onEnd: @escaping () -> Void) {
        self.onBegin = onBegin
        self.onEnd = onEnd
    }

    func start() {
        attachTap()
    }

    func stop() {
        retryTimer?.invalidate(); retryTimer = nil
        holdWatchdog?.invalidate(); holdWatchdog = nil
        if let tap = tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        tap = nil; runLoopSource = nil
    }

    private func attachTap() {
        guard tap == nil else { return }

        let mask = (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
            // Returning nil consumes the event so macOS never switches input source.
            return monitor.handleEvent(type, event) ? nil : Unmanaged.passUnretained(event)
        }

        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,                // ACTIVE tap: lets us swallow fn
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            let msg = AXIsProcessTrusted()
                ? "fn unavailable — tap creation failed"
                : "fn off — grant Accessibility (auto-engages)"
            report(false, msg)
            scheduleRetry()
            return
        }

        tap = newTap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        retryTimer?.invalidate(); retryTimer = nil
        NSLog("Najwa: fn event tap installed and enabled.")
        report(true, "fn ready — hold to dictate, double-tap to lock")
    }

    private func scheduleRetry() {
        guard retryTimer == nil else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.attachTap()
        }
    }

    private func report(_ active: Bool, _ msg: String) {
        DispatchQueue.main.async { [weak self] in self?.onStatus?(active, msg) }
    }

    /// Returns true if the event should be consumed (swallowed). Runs on the main
    /// run loop (the tap is attached there), so it touches state directly.
    private func handleEvent(_ type: CGEventType, _ event: CGEvent) -> Bool {
        // The system can disable a tap; re-enable it so fn keeps working.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = tap { CGEvent.tapEnable(tap: tap, enable: true) }
            NSLog("Najwa: fn tap was disabled by system; re-enabled.")
            return false
        }
        let fnDown = event.flags.contains(.maskSecondaryFn)
        guard fnDown != lastFnDown else { return false } // other modifier — pass through
        lastFnDown = fnDown
        if fnDown { fnPressed() } else { fnReleased() }
        return true // consume fn so macOS doesn't switch input source
    }

    private func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }

    private func fnPressed() {
        switch mode {
        case .idle:
            keyDownTime = now()
            mode = .holding
            startHoldWatchdog()
            onBegin()
        case .tapPending:
            pendingWork?.cancel()
            mode = .locked          // second tap → lock on (already recording)
        case .locked:
            keyDownTime = now()
            mode = .stopArming
        case .stopArming:
            pendingWork?.cancel()
            mode = .idle            // confirming double-tap → stop
            onEnd()
        case .holding:
            break
        }
    }

    private func fnReleased() {
        stopHoldWatchdog()
        switch mode {
        case .holding:
            if now() - keyDownTime > holdMin {
                mode = .idle
                onEnd()             // hold-to-talk finished
            } else {
                mode = .tapPending
                schedule(after: tapWindow) { [weak self] in
                    guard let self, self.mode == .tapPending else { return }
                    self.mode = .idle
                    self.onEnd()    // short single-tap dictation
                }
            }
        case .stopArming:
            schedule(after: tapWindow) { [weak self] in
                guard let self, self.mode == .stopArming else { return }
                self.mode = .locked // stray tap; stay locked
            }
        default:
            break
        }
    }

    // Safety net: if the OS ever drops the fn-release event, detect that the key
    // is physically up and recover by ending the hold.
    private func startHoldWatchdog() {
        holdWatchdog?.invalidate()
        holdWatchdog = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            guard let self, self.mode == .holding else { return }
            let fnDown = CGEventSource.flagsState(.combinedSessionState).contains(.maskSecondaryFn)
            if !fnDown { self.lastFnDown = false; self.fnReleased() } // missed release; recover
        }
    }

    private func stopHoldWatchdog() {
        holdWatchdog?.invalidate()
        holdWatchdog = nil
    }

    private func schedule(after: TimeInterval, _ block: @escaping () -> Void) {
        pendingWork?.cancel()
        let work = DispatchWorkItem(block: block)
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + after, execute: work)
    }
}
