import Foundation

/// Reads newline-delimited JSON. Malformed lines are skipped and counted,
/// never thrown — agent transcript formats are undocumented and drift.
public enum TolerantJSONL {
    public static func objects(at url: URL) throws -> (objects: [[String: Any]], skippedLines: Int) {
        let data = try Data(contentsOf: url)
        let text = String(decoding: data, as: UTF8.self)
        var objects: [[String: Any]] = []
        var skipped = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let d = trimmed.data(using: .utf8),
               let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] {
                objects.append(obj)
            } else {
                skipped += 1
            }
        }
        return (objects, skipped)
    }
}
