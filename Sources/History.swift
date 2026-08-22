import Foundation
import Combine

struct Utterance: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var text: String
    /// Seconds of audio recorded.
    var duration: Double
    /// Seconds whisper took to decode it.
    var latency: Double
    /// App that was frontmost when dictation began.
    var appName: String

    var wordCount: Int { text.split(whereSeparator: \.isWhitespace).count }
}

/// Dictation history, persisted as one JSON array.
///
/// ponytail: whole-file rewrite per entry. At a few hundred short strings this
/// is microseconds; swap for append-only JSONL if history ever gets large.
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published private(set) var entries: [Utterance] = []

    private let io = DispatchQueue(label: "yapperroni.history")
    private let url = Config.supportDir.appendingPathComponent("history.json")

    private init() { load() }

    // MARK: - Derived stats

    var totalWords: Int { entries.reduce(0) { $0 + $1.wordCount } }
    var totalSeconds: Double { entries.reduce(0) { $0 + $1.duration } }
    var averageLatency: Double {
        guard !entries.isEmpty else { return 0 }
        return entries.reduce(0) { $0 + $1.latency } / Double(entries.count)
    }
    /// Rough: assumes 40 wpm typing as the counterfactual.
    var minutesSaved: Double { Double(totalWords) / 40.0 - totalSeconds / 60.0 }

    func filtered(_ query: String) -> [Utterance] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return entries }
        return entries.filter { $0.text.localizedCaseInsensitiveContains(q) }
    }

    // MARK: - Mutation

    func add(_ u: Utterance) {
        guard Settings.shared.historyEnabled else { return }
        entries.insert(u, at: 0)
        let limit = max(1, Settings.shared.historyLimit)
        if entries.count > limit { entries.removeLast(entries.count - limit) }
        save()
    }

    func delete(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        entries.removeAll { ids.contains($0.id) }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    func exportText() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return entries.reversed()
            .map { "[\(f.string(from: $0.date))] \($0.text)" }
            .joined(separator: "\n")
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Utterance].self, from: data)
        else { return }
        entries = decoded
    }

    private func save() {
        let snapshot = entries
        io.async { [url] in
            try? FileManager.default.createDirectory(
                at: Config.supportDir, withIntermediateDirectories: true)
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}
