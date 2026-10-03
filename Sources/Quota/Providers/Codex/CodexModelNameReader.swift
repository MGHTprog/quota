import Foundation

/// Reads model metadata only; no conversation text is exposed or logged.
final class CodexModelNameReader {
    private let home: URL
    private let lock = NSLock()
    private var cached: String?
    private var cacheDate = Date.distantPast

    init(home: URL? = nil) {
        self.home = home ?? ProcessInfo.processInfo.environment["CODEX_HOME"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }

    func displayName(fallback: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        if let cached, Date().timeIntervalSince(cacheDate) < 30 { return cached }
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        let files = FileManager.default.enumerator(
            at: home.appendingPathComponent("sessions"),
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )?.compactMap { item -> (URL, Date)? in
            guard let url = item as? URL, url.pathExtension == "jsonl",
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { return nil }
            return (url, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.1 > $1.1 } ?? []

        var latest: (timestamp: String, model: String)?
        for (url, _) in files.prefix(20) {
            guard let file = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? file.close() }
            guard let size = try? file.seekToEnd() else { continue }
            try? file.seek(toOffset: size > 2_097_152 ? size - 2_097_152 : 0)
            guard let data = try? file.readToEnd(), let text = String(data: data, encoding: .utf8) else { continue }
            if let session = Self.latestModel(in: text),
               latest == nil || session.timestamp > latest!.timestamp {
                latest = session
            }
        }
        let result = latest.map { Self.format($0.model) } ?? fallback
        cached = result
        cacheDate = Date()
        return result
    }

    static func latestModel(in text: String) -> (timestamp: String, model: String)? {
        var latest: (timestamp: String, model: String)?
        for line in text.split(separator: "\n") where line.contains("turn_context") {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  object["type"] as? String == "turn_context",
                  let timestamp = object["timestamp"] as? String,
                  let payload = object["payload"] as? [String: Any],
                  let model = payload["model"] as? String, !model.isEmpty,
                  model != "codex-auto-review" else { continue }
            if latest == nil || timestamp > latest!.timestamp { latest = (timestamp, model) }
        }
        return latest
    }

    static func format(_ model: String) -> String {
        guard model.hasPrefix("gpt-") else { return model }
        return "GPT-" + model.dropFirst(4).split(separator: "-").enumerated().map { index, part in
            index == 0 ? String(part) : part.capitalized
        }.joined(separator: " ")
    }
}
