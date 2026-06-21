import Foundation

/// In-memory only. Cleaned-text entries are kept for at most 6 hours of app
/// uptime, swept by a timer, and lost entirely when the app quits. Nothing is
/// ever written to disk.
final class HistoryStore {
    struct Entry { let text: String; let created: Date }

    private var entries: [Entry] = []
    private let lock = NSLock()
    private let ttl: TimeInterval = 6 * 60 * 60
    private var timer: Timer?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.sweep()
        }
    }

    func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lock.lock(); entries.append(Entry(text: trimmed, created: Date())); lock.unlock()
    }

    func recent() -> [Entry] {
        sweep()
        lock.lock(); defer { lock.unlock() }
        return entries
    }

    private func sweep() {
        let cutoff = Date().addingTimeInterval(-ttl)
        lock.lock(); entries.removeAll { $0.created < cutoff }; lock.unlock()
    }

    deinit { timer?.invalidate() }
}
