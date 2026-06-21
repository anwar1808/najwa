import AppKit
import CoreGraphics

/// Watches the `fn` (Globe) key via a CGEventTap and turns raw key transitions
/// into two semantic events: begin-recording and end-recording.
///
/// State machine (one key serves both modes). A "tap" is a quick down+up; a
/// "double-tap" is two taps inside `tapWindow`.
///
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

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

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
        let mask = (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, _, event, refcon in
            if let refcon = refcon {
                Unmanaged<HotkeyMonitor>.fromOpaque(refcon)
                    .takeUnretainedValue()
                    .handleFlags(event)
            }
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("Najwa: failed to create fn event tap (needs Accessibility permission).")
            return
        }
        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("Najwa: fn event tap installed.")
    }

    func stop() {
        if let tap = tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
    }

    private func handleFlags(_ event: CGEvent) {
        let fnDown = event.flags.contains(.maskSecondaryFn)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if fnDown { self.fnPressed() } else { self.fnReleased() }
        }
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

    private func schedule(after: TimeInterval, _ block: @escaping () -> Void) {
        pendingWork?.cancel()
        let work = DispatchWorkItem(block: block)
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + after, execute: work)
    }
}
