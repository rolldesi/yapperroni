import Foundation

/// The user's custom word list.
///
/// Parsing lives here rather than inside Whisper so the settings UI can show
/// exactly what was parsed — the surest way to prove the separator works is to
/// display the terms back.
enum Vocabulary {
    /// Terms are separated by commas or newlines, so a list can be typed either
    /// way — "gooning, codex, Yapperroni" or one per line — and pasted from
    /// anywhere without reformatting.
    static func terms(_ raw: String) -> [String] {
        raw.split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Adds a term if it is not already present (case-insensitively) and
    /// returns the new list text. Returns nil when nothing changed.
    static func adding(_ term: String, to raw: String) -> String? {
        let new = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !new.isEmpty else { return nil }
        var existing = terms(raw)
        guard !existing.contains(where: { $0.caseInsensitiveCompare(new) == .orderedSame })
        else { return nil }
        existing.append(new)
        return existing.joined(separator: ", ")
    }

    /// The glossary handed to Whisper as an initial prompt.
    ///
    /// Capped: the prompt shares the decoder's context with the audio, and an
    /// overlong list starts costing accuracy instead of adding it.
    static func prompt(_ raw: String, limit: Int = 380) -> String? {
        let list = terms(raw)
        guard !list.isEmpty else { return nil }
        var out = "Glossary: "
        for t in list {
            if out.count + t.count > limit { break }
            out += t + ", "
        }
        return out.hasSuffix(", ") ? String(out.dropLast(2)) + "." : out
    }
}
