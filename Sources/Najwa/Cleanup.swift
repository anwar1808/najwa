import Foundation
import FoundationModels

/// Polishes raw transcript text with Apple's on-device Foundation Model:
/// strips filler words, fixes punctuation/capitalisation, light formatting.
/// Fully on-device; no text leaves the machine. Falls back to a naive local
/// tidy if the model is unavailable.
struct Cleanup {
    private let instructions = """
    You clean up dictated speech. Remove filler words (um, uh, like, you know) \
    and false starts. Fix capitalisation and punctuation. Keep the speaker's \
    wording and meaning — do not summarise, answer, or add content. Output only \
    the cleaned text.
    """

    func polish(_ raw: String) async -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default
            if case .available = model.availability {
                do {
                    let session = LanguageModelSession(instructions: instructions)
                    let response = try await session.respond(to: trimmed)
                    let cleaned = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    return cleaned.isEmpty ? naiveTidy(trimmed) : normalizeSpacing(cleaned)
                } catch {
                    NSLog("Najwa: Foundation Models cleanup failed: \(error.localizedDescription)")
                }
            } else {
                NSLog("Najwa: on-device model unavailable; using naive tidy.")
            }
        }
        return naiveTidy(trimmed)
    }

    /// Deterministic spacing fix so sentences always read like written prose,
    /// regardless of how the language model spaced them. Inserts a missing space
    /// after `.` `!` `?` between sentences, and collapses doubled spaces after them.
    /// Conservative: requires a letter before and a capital after, so it leaves
    /// decimals (3.14), ellipses, and abbreviations like "U.S." alone.
    private func normalizeSpacing(_ s: String) -> String {
        var out = s
        out = regexReplace(out, #"([A-Za-z])([.!?])([A-Z])"#, "$1$2 $3")
        out = regexReplace(out, #"([.!?]) {2,}"#, "$1 ")
        return out
    }

    private func regexReplace(_ s: String, _ pattern: String, _ template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        return re.stringByReplacingMatches(in: s, range: range, withTemplate: template)
    }

    private func naiveTidy(_ s: String) -> String {
        var out = s
        if let first = out.first, first.isLowercase {
            out.replaceSubrange(out.startIndex...out.startIndex, with: String(first).uppercased())
        }
        let last = out.last
        if last != "." && last != "!" && last != "?" { out += "." }
        return normalizeSpacing(out)
    }
}
