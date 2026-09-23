import AppKit

/// Personal vocabulary for dictation: the names, clients, products and tools
/// Whisper tends to mishear. Shared with Pensieve — both apps read the same
/// `.corrections.json`, so a correction added in Pensieve's dictionary panel
/// applies to the next dictation with no rebuild.
///
/// Three uses, all local:
///   1. `promptText`  — fed to Whisper as its conditioning prompt, so it is
///                      biased towards the right spellings at decode time.
///   2. `apply(to:)`  — after decoding: exact replacements first ("Paykel" →
///                      PayCal), then a sound-alike pass for words the spell
///                      checker doesn't know (a novel misspelling of a term).
///   3. `isPromptEcho`— guard: Whisper can parrot the prompt on near-silence.
///
/// Scopes read: `global` (Pensieve's "All projects") and the `najwa` project
/// entry (dictation-only). Project scopes such as Umbra/Defra are deliberately
/// NOT read: rules like "Eve → ETH" are only safe inside their project, and a
/// dictation has no project.
///
/// Rollback: the whole feature sits behind `Vocabulary.isEnabled`
/// (UserDefaults `NajwaVocabEnabled`, menu toggle). Off = the pre-vocabulary
/// pipeline exactly: no prompt tokens, no replacements.
final class Vocabulary {
    static let shared = Vocabulary()

    static let enabledKey = "NajwaVocabEnabled"
    static let promptKey = "NajwaVocabPrompt"
    static let promptTermsKey = "NajwaPromptTerms"
    static let pathKey = "NajwaGlossaryPath"
    static let defaultPath = NSString(string: "~/Annie-Claude/Pensieve/Pensieve/.corrections.json").expandingTildeInPath
    /// Whisper's prompt window is 224 tokens; 60 terms ≈ 150 tokens (Pensieve
    /// uses the same cap). More than this and terms get silently truncated.
    static let maxPromptTerms = 60
    /// Default prompt size when biasing is on. Measured 23 Sep 2026 (M4 Max,
    /// large-v3, 5.4 s clip): every prompted term costs decode time because
    /// WhisperKit force-feeds each token and drops its prefill cache —
    /// 5 terms ≈ +0.2 s, 10 ≈ +0.35 s, 20 ≈ +0.65 s, 60 ≈ +0.95 s over the
    /// ~0.85 s baseline. Hence biasing is OFF by default and the post-decode
    /// pass (≈0 ms) does the work; turn biasing on for a short, high-value list.
    static let defaultPromptTerms = 12

    struct Snapshot {
        var replacements: [(wrong: String, right: String)] = []
        var terms: [String] = []
        var loadedFrom: String = ""
        var error: String?
        var isEmpty: Bool { replacements.isEmpty && terms.isEmpty }
    }

    private(set) var snapshot = Snapshot()
    private var lastModified: Date?
    private let lock = NSLock()

    var isEnabled: Bool {
        get { Self.bool(Self.enabledKey, default: true) }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) }
    }

    /// `bool(forKey:)` so a command-line override (`-NajwaVocabPrompt YES`,
    /// stored as a string) parses the same way as a saved preference.
    private static func bool(_ key: String, default d: Bool) -> Bool {
        let ud = UserDefaults.standard
        return ud.object(forKey: key) == nil ? d : ud.bool(forKey: key)
    }

    /// Whether the term list is also sent to Whisper as a decode prompt.
    /// Off by default: it costs real latency (see `defaultPromptTerms`).
    var isPromptEnabled: Bool {
        get { Self.bool(Self.promptKey, default: false) }
        set { UserDefaults.standard.set(newValue, forKey: Self.promptKey) }
    }

    var promptTermLimit: Int {
        let n = UserDefaults.standard.integer(forKey: Self.promptTermsKey)
        return min(Self.maxPromptTerms, n > 0 ? n : Self.defaultPromptTerms)
    }

    var path: String {
        UserDefaults.standard.string(forKey: Self.pathKey) ?? Self.defaultPath
    }

    /// One-line status for the menu.
    var status: String {
        guard isEnabled else { return "vocab: off" }
        if let e = snapshot.error { return "vocab: \(e)" }
        let bias = isPromptEnabled ? ", biasing Whisper with \(min(promptTermLimit, snapshot.terms.count))" : ""
        return "vocab: \(snapshot.terms.count) terms, \(snapshot.replacements.count) rules\(bias)"
    }

    // MARK: - Loading

    /// Re-reads the file only when its modification date changed. Cheap enough
    /// to call at the start of every dictation.
    @discardableResult
    func reloadIfChanged(force: Bool = false) -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        let url = URL(fileURLWithPath: path)
        let mtime = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
        if !force, let mtime, let last = lastModified, mtime == last { return snapshot }
        lastModified = mtime
        snapshot = Self.parse(url: url)
        if let e = snapshot.error {
            NSLog("Najwa: vocabulary not loaded (\(e))")
        } else {
            NSLog("Najwa: vocabulary loaded — \(snapshot.terms.count) terms, \(snapshot.replacements.count) rules from \(url.lastPathComponent)")
        }
        return snapshot
    }

    private static func parse(url: URL) -> Snapshot {
        var snap = Snapshot(loadedFrom: url.path)
        guard let data = try? Data(contentsOf: url) else {
            snap.error = "file not found"; return snap
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            snap.error = "bad JSON"; return snap
        }
        var scopes: [[String: Any]] = []
        if let g = root["global"] as? [String: Any] { scopes.append(g) }
        if let projects = root["projects"] as? [String: Any],
           let n = projects["najwa"] as? [String: Any] { scopes.append(n) }

        var seenTerms = Set<String>()
        var seenWrong = Set<String>()
        for scope in scopes {
            if let repl = scope["replacements"] as? [String: String] {
                // Longest "wrong" first so multi-word rules win over their parts.
                for (wrong, right) in repl.sorted(by: { $0.key.count > $1.key.count }) {
                    let w = wrong.trimmingCharacters(in: .whitespaces)
                    let r = right.trimmingCharacters(in: .whitespaces)
                    guard !w.isEmpty, !r.isEmpty, seenWrong.insert(w.lowercased()).inserted else { continue }
                    snap.replacements.append((w, r))
                }
            }
            if let terms = scope["terms"] as? [String] {
                for t in terms {
                    let tt = t.trimmingCharacters(in: .whitespaces)
                    if !tt.isEmpty, seenTerms.insert(tt.lowercased()).inserted { snap.terms.append(tt) }
                }
            }
        }
        // Every replacement target is also a term worth biasing towards.
        for (_, r) in snap.replacements where seenTerms.insert(r.lowercased()).inserted {
            snap.terms.append(r)
        }
        snap.replacements.sort { $0.wrong.count > $1.wrong.count }
        return snap
    }

    // MARK: - 1. Whisper prompt

    /// Conditioning text for the decoder, or nil when disabled/empty. Phrased
    /// as a glossary line (Pensieve does the same) rather than fake prior
    /// speech, which keeps the echo case recognisable — see `isPromptEcho`.
    var promptText: String? {
        guard isEnabled, isPromptEnabled else { return nil }
        let terms = snapshot.terms.prefix(promptTermLimit)
        guard !terms.isEmpty else { return nil }
        return "Glossary: " + terms.joined(separator: ", ") + "."
    }

    // MARK: - 2. Post-decode correction

    /// Exact replacements (whole-word, case-insensitive, longest first), then
    /// a sound-alike pass over words the spell checker doesn't know.
    func apply(to text: String) -> String {
        guard isEnabled, !snapshot.isEmpty, !text.isEmpty else { return text }
        var out = text
        for (wrong, right) in snapshot.replacements {
            out = Self.replaceWholeWord(wrong, with: right, in: out)
        }
        out = soundAlikePass(out)
        if out != text {
            // Log counts only — dictated content never goes to disk.
            NSLog("Najwa: vocabulary corrected \(Self.differingWordCount(text, out)) word(s)")
        }
        return out
    }

    private static func replaceWholeWord(_ wrong: String, with right: String, in text: String) -> String {
        let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: wrong) + "(?![\\p{L}\\p{N}])"
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return re.stringByReplacingMatches(in: text, range: range,
                                           withTemplate: NSRegularExpression.escapedTemplate(for: right))
    }

    /// Only single words the system spell checker flags as unknown are
    /// candidates — so "pensive" (a real word) is left alone unless there is an
    /// explicit rule, while "Paykel" or "Evangelio" can be matched by sound.
    /// A candidate is corrected when its phonetic key is within one edit of a
    /// term's key and both start with the same sound.
    private func soundAlikePass(_ text: String) -> String {
        let termKeys: [(term: String, key: String)] = snapshot.terms
            .filter { !$0.contains(" ") && $0.count >= 4 }
            .map { ($0, Phonetic.key($0)) }
        guard !termKeys.isEmpty else { return text }
        let termSet = Set(snapshot.terms.map { $0.lowercased() })

        guard let re = try? NSRegularExpression(pattern: "[\\p{L}][\\p{L}'’-]{2,}") else { return text }
        let ns = text as NSString
        let checker = NSSpellChecker.shared
        var result = text
        // Replace from the end so earlier ranges stay valid.
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            let word = ns.substring(with: m.range)
            let lower = word.lowercased()
            if termSet.contains(lower) { continue }
            let miss = checker.checkSpelling(of: word, startingAt: 0, language: "en_GB", wrap: false,
                                             inSpellDocumentWithTag: 0, wordCount: nil)
            guard miss.location != NSNotFound else { continue }  // known English word: leave it
            let key = Phonetic.key(word)
            guard key.count >= 2 else { continue }
            var best: (term: String, dist: Int)?
            for (term, tkey) in termKeys where tkey.first == key.first {
                let d = Phonetic.editDistance(key, tkey)
                if d <= 1, d < (best?.dist ?? Int.max) { best = (term, d) }
            }
            guard let hit = best else { continue }
            let r = NSRange(location: m.range.location, length: m.range.length)
            result = (result as NSString).replacingCharacters(in: r, with: hit.term)
        }
        return result
    }

    private static func differingWordCount(_ a: String, _ b: String) -> Int {
        let wa = a.split(separator: " "), wb = b.split(separator: " ")
        return max(1, zip(wa, wb).filter { $0 != $1 }.count + abs(wa.count - wb.count))
    }

    // MARK: - 3. Prompt-echo guard

    /// True when the decoded text is just the prompt coming back: it starts
    /// with "Glossary", or it is three or more glossary terms and nothing else.
    /// (A real one- or two-term dictation, "PayCal", passes through.)
    func isPromptEcho(_ text: String) -> Bool {
        guard isEnabled else { return false }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.lowercased().hasPrefix("glossary") { return true }
        let termSet = Set(snapshot.terms.map { $0.lowercased() })
        let words = t.split(whereSeparator: { $0 == "," || $0 == " " })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?…")).lowercased() }
            .filter { !$0.isEmpty }
        return words.count >= 3 && words.allSatisfy { termSet.contains($0) }
    }
}

/// A compact sound key: a simplified metaphone-style reduction good enough to
/// group "Evangelio"/"Evangelou"/"Evangelo" or "Paykel"/"PayCal" together.
enum Phonetic {
    static func key(_ word: String) -> String {
        var s = word.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .filter { $0.isLetter }
        guard !s.isEmpty else { return "" }
        // Digraphs and silent-letter conventions first. A leading "gh" is a
        // hard g (Ghostty); elsewhere it is silent (Hyperact has none, "light").
        if s.hasPrefix("gh") { s = "g" + s.dropFirst(2) }
        let pairs: [(String, String)] = [
            ("ph", "f"), ("gh", ""), ("ck", "k"), ("sch", "sk"), ("sh", "x"), ("ch", "x"),
            ("th", "0"), ("wh", "w"), ("qu", "kw"), ("kn", "n"), ("wr", "r"), ("dg", "j"),
            ("tio", "xo"), ("sio", "xo"), ("ci", "si"), ("ce", "se"), ("cy", "sy"),
        ]
        for (a, b) in pairs { s = s.replacingOccurrences(of: a, with: b) }
        var out = ""
        for (i, c) in s.enumerated() {
            var ch = c
            switch ch {
            case "c", "q": ch = "k"
            case "z": ch = "s"
            case "v": ch = "f"
            case "y": ch = i == 0 ? "y" : "i"
            case "x": ch = "x"
            default: break
            }
            // Keep a leading vowel, drop the rest (that is what makes
            // pay-cal ≈ paykel), and collapse doubled consonants.
            let isVowel = "aeiou".contains(ch)
            if isVowel && i != 0 { continue }
            if let last = out.last, last == ch { continue }
            out.append(ch)
        }
        return out
    }

    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count), cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }
}
