import Foundation
import IOKit
import IOKit.hid

/// Detects the **fn / Globe** key at the IOKit HID device layer via IOHIDManager.
/// The fn key reports on a separate Apple "Top Case" HID device (usage page
/// 0xff00, usage 0x03), distinct from the main keyboard. We read it (no seize).
/// To stop macOS switching input source on fn, the Globe key must be set to
/// "Do Nothing" in System Settings (keyboard switching stays on Ctrl+Space).
///
/// Emits two semantic events — begin and end — via the same hold / double-tap
/// state machine:
///   key down            -> begin immediately
///   release > holdMin    -> end (hold-to-talk)
///   quick tap            -> wait tapWindow; second tap => LOCKED, else end
///   in LOCKED, double-tap-> end
final class HotkeyMonitor {
    private let onBegin: () -> Void
    private let onEnd: () -> Void

    /// (active, humanReadableStatus) — surfaced in the menu.
    var onStatus: ((Bool, String) -> Void)?

    private var manager: IOHIDManager?

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
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        // Match the Apple Top Case device(s) that carry the fn/Globe key.
        let matches: [[String: Any]] = [
            [kIOHIDDeviceUsagePageKey: 0xff00, kIOHIDDeviceUsageKey: 0x0003],
            [kIOHIDDeviceUsagePageKey: 0x00ff, kIOHIDDeviceUsageKey: 0x0003],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(mgr, matches as CFArray)

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        let valueCallback: IOHIDValueCallback = { context, _, _, value in
            guard let context = context else { return }
            Unmanaged<HotkeyMonitor>.fromOpaque(context).takeUnretainedValue().handle(value)
        }
        IOHIDManagerRegisterInputValueCallback(mgr, valueCallback, ctx)
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

        // Shared read (no seize) — Right Option needs no suppression.
        let result = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = mgr

        if result == kIOReturnSuccess {
            report(true, "ready (fn)")
            NSLog("Najwa: IOHIDManager open ok (fn).")
        } else {
            report(false, "off — grant Input Monitoring, then relaunch")
            NSLog("Najwa: IOHIDManager open failed (\(result)). Needs Input Monitoring.")
        }
    }

    func stop() {
        pendingWork?.cancel()
        if let mgr = manager {
            IOHIDManagerUnscheduleFromRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
    }

    private func report(_ active: Bool, _ msg: String) {
        DispatchQueue.main.async { [weak self] in self?.onStatus?(active, msg) }
    }

    /// Called from the HID run-loop source (main thread) for each fn value report.
    private func handle(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        // fn / Globe: usage 0x03 on an Apple vendor / top-case page.
        guard usage == 0x03, usagePage == 0xff00 || usagePage == 0x00ff else { return }
        let down = IOHIDValueGetIntegerValue(value) != 0
        if down { fnPressed() } else { fnReleased() }
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
