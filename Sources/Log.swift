import Foundation

/// Append-only diagnostic log.
///
/// Every silent-failure path in this app (gate rejects the utterance, tap never
/// fires, paste goes nowhere) looks identical from the outside: nothing
/// happens. One line per utterance makes them distinguishable.
enum Log {
    private static let queue = DispatchQueue(label: "yapperroni.log")
    private static let url = Config.supportDir.appendingPathComponent("yapperroni.log")

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    /// Synchronous on purpose: `exit()` discards queued async writes, which
    /// loses exactly the last line — the one saying why we exited.
    static func write(_ line: String) {
        queue.sync {
            let entry = "\(stamp.string(from: Date()))  \(line)\n"
            guard let data = entry.data(using: .utf8) else { return }
            try? FileManager.default.createDirectory(at: Config.supportDir, withIntermediateDirectories: true)
            if let h = try? FileHandle(forWritingTo: url) {
                defer { try? h.close() }
                try? h.seekToEnd()
                try? h.write(contentsOf: data)  // best effort
            } else {
                try? data.write(to: url)
            }
        }
    }

    static var path: String { url.path }
}
