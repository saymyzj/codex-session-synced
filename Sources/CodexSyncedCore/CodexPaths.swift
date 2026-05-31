import Foundation

struct ParsedConfig {
    var rootValues: [String: String]
    var providerSections: [String: [String: String]]
}

enum ConfigParser {
    static func parse(url: URL) -> ParsedConfig {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return ParsedConfig(rootValues: [:], providerSections: [:])
        }

        var rootValues: [String: String] = [:]
        var providerSections: [String: [String: String]] = [:]
        var currentSection: String?

        for rawLine in content.components(separatedBy: .newlines) {
            let line = stripComment(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("[") && line.hasSuffix("]") {
                currentSection = String(line.dropFirst().dropLast())
                continue
            }

            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = unquote(parts[1].trimmingCharacters(in: .whitespacesAndNewlines))

            if let section = currentSection {
                if section.hasPrefix("model_providers.") {
                    let provider = String(section.dropFirst("model_providers.".count)).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    providerSections[provider, default: [:]][key] = value
                }
            } else {
                rootValues[key] = value
            }
        }

        return ParsedConfig(rootValues: rootValues, providerSections: providerSections)
    }

    private static func stripComment(_ line: String) -> String {
        var inQuote = false
        var result = ""
        for character in line {
            if character == "\"" { inQuote.toggle() }
            if character == "#", !inQuote { break }
            result.append(character)
        }
        return result
    }

    private static func unquote(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("\""), trimmed.hasSuffix("\""), trimmed.count >= 2 {
            trimmed.removeFirst()
            trimmed.removeLast()
        }
        return trimmed
    }
}

public enum CodexPathResolver {
    public static func effectiveCodexHome(settings: AppSettings) -> URL {
        settings.codexHome.standardizedFileURL
    }

    static func effectiveSQLiteHome(settings: AppSettings, parsedConfig: ParsedConfig) -> URL {
        if let explicit = settings.sqliteHome {
            return explicit.standardizedFileURL
        }
        if let configValue = parsedConfig.rootValues["sqlite_home"], !configValue.isEmpty {
            return expandTilde(configValue).standardizedFileURL
        }
        return settings.codexHome.standardizedFileURL
    }

    static func expandTilde(_ path: String) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded)
    }
}
