import Foundation

enum RolloutRepairer {
    static func makeRepair(url: URL, targetProvider: String) -> RolloutRepair? {
        guard let firstLine = firstLine(url: url) else { return nil }
        guard let data = firstLine.data(using: .utf8),
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["type"] as? String == "session_meta",
              var payload = object["payload"] as? [String: Any] else {
            return nil
        }

        let current = payload["model_provider"] as? String
        guard current != targetProvider else { return nil }
        payload["model_provider"] = targetProvider
        object["payload"] = payload

        guard let repairedData = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let repairedLine = String(data: repairedData, encoding: .utf8) else {
            return nil
        }

        let sessionID = payload["id"] as? String ?? url.deletingPathExtension().lastPathComponent
        return RolloutRepair(
            id: url.path,
            url: url,
            sessionID: sessionID,
            currentProvider: current,
            targetProvider: targetProvider,
            originalFirstLine: firstLine,
            repairedFirstLine: repairedLine
        )
    }

    static func apply(_ repair: RolloutRepair) throws {
        let data = try Data(contentsOf: repair.url)
        guard let content = String(data: data, encoding: .utf8) else { return }
        let newContent: String
        if let newlineRange = content.range(of: "\n") {
            newContent = repair.repairedFirstLine + content[newlineRange.lowerBound...]
        } else {
            newContent = repair.repairedFirstLine + "\n"
        }
        try newContent.write(to: repair.url, atomically: true, encoding: .utf8)
    }

    static func restore(url: URL, firstLine: String) throws {
        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) else { return }
        let newContent: String
        if let newlineRange = content.range(of: "\n") {
            newContent = firstLine + content[newlineRange.lowerBound...]
        } else {
            newContent = firstLine + "\n"
        }
        try newContent.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func firstLine(url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var line = Data()
        while true {
            let chunk: Data
            do {
                chunk = try handle.read(upToCount: 64 * 1024) ?? Data()
            } catch {
                return nil
            }
            guard !chunk.isEmpty else { break }
            if let newline = chunk.firstIndex(of: UInt8(ascii: "\n")) {
                line.append(contentsOf: chunk[..<newline])
                break
            }
            line.append(chunk)
        }
        if line.last == UInt8(ascii: "\r") {
            line.removeLast()
        }
        return String(data: line, encoding: .utf8)
    }
}
