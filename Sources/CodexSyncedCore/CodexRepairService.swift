import AppKit
import Foundation

public enum CodexRepairError: LocalizedError {
    case noStateDatabase(URL)
    case codexIsRunning
    case noScanResult
    case noBackupManifest(URL)

    public var errorDescription: String? {
        switch self {
        case .noStateDatabase(let url): "未找到状态库：\(url.path)"
        case .codexIsRunning: "检测到 Codex 正在运行，请退出 Codex 后再修复。"
        case .noScanResult: "请先扫描待修复项。"
        case .noBackupManifest(let url): "未找到备份描述文件：\(url.path)"
        }
    }
}

public final class CodexRepairService {
    public init() {}

    public func isCodexRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            app.bundleIdentifier == "com.openai.codex" || app.localizedName == "Codex"
        }
    }

    public func openCodex() {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Codex.app"))
        }
    }

    public func openDirectory(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    public func scan(settings: AppSettings) throws -> ScanResult {
        let codexHome = CodexPathResolver.effectiveCodexHome(settings: settings)
        let configURL = codexHome.appendingPathComponent("config.toml")
        let parsedConfig = ConfigParser.parse(url: configURL)
        let sqliteHome = CodexPathResolver.effectiveSQLiteHome(settings: settings, parsedConfig: parsedConfig)
        let providerInfo = providerInfo(parsedConfig: parsedConfig, configURL: configURL)
        let state = latestStateDatabase(in: sqliteHome)

        var threads: [ThreadRow] = []
        if let state {
            let db = try SQLiteDatabase(path: state.url.path, readonly: true)
            threads = try db.queryThreads()
        }

        let sqliteProviderUpdates = threads.filter { $0.modelProvider != providerInfo.provider }
        let sqliteCompatibilityUpdates = threads.filter { !$0.hasUserEvent || $0.cwd.isEmpty || ($0.threadSource ?? "").isEmpty }
        let rolloutRoots = [
            codexHome.appendingPathComponent("sessions"),
            codexHome.appendingPathComponent("archived_sessions")
        ]
        let rolloutRepairs = FileUtilities.rolloutFiles(under: rolloutRoots).compactMap {
            RolloutRepairer.makeRepair(url: $0, targetProvider: providerInfo.provider)
        }
        let indexRepairs = missingIndexRepairs(codexHome: codexHome, threads: threads)
        let backups = loadBackups(codexHome: codexHome)
        let lastRepairAt = backups.sorted { $0.createdAt > $1.createdAt }.first?.createdAt

        return ScanResult(
            providerInfo: providerInfo,
            stateDatabase: state,
            threads: threads,
            sqliteProviderUpdates: sqliteProviderUpdates,
            sqliteCompatibilityUpdates: sqliteCompatibilityUpdates,
            rolloutRepairs: rolloutRepairs,
            indexRepairs: indexRepairs,
            backups: backups,
            codexHome: codexHome,
            sqliteHome: sqliteHome,
            lastRepairAt: lastRepairAt
        )
    }

    public func repair(scan: ScanResult, settings: AppSettings, mode: BackupMode) throws -> BackupRecord? {
        guard !isCodexRunning() else { throw CodexRepairError.codexIsRunning }
        guard let state = scan.stateDatabase else { throw CodexRepairError.noStateDatabase(scan.sqliteHome) }
        guard scan.hasRepairs else { return nil }

        let backup = try createBackup(scan: scan, settings: settings, mode: mode)
        let db = try SQLiteDatabase(path: state.url.path, readonly: false)
        try db.updateProvider(threadIDs: scan.sqliteProviderUpdates.map(\.id), provider: scan.providerInfo.provider)
        try db.updateCompatibility(threadIDs: scan.sqliteCompatibilityUpdates.map(\.id))
        for repair in scan.rolloutRepairs {
            try RolloutRepairer.apply(repair)
        }
        try appendMissingIndexEntries(scan.indexRepairs, codexHome: scan.codexHome)
        try rotateBackups(codexHome: scan.codexHome, mode: mode, limit: mode == .full ? settings.fullLimit : settings.lightweightLimit)
        return backup
    }

    public func restore(backup: BackupRecord) throws {
        guard !isCodexRunning() else { throw CodexRepairError.codexIsRunning }
        let backupURL = URL(fileURLWithPath: backup.path)
        let manifestURL = backupURL.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL) else {
            throw CodexRepairError.noBackupManifest(manifestURL)
        }
        let manifest = try JSONDecoder.codexSynced.decode(BackupManifest.self, from: data)
        let fm = FileManager.default
        for item in manifest.files {
            let source = backupURL.appendingPathComponent(item.backupRelativePath)
            let destination = URL(fileURLWithPath: item.originalPath)
            try FileUtilities.ensureDirectory(destination.deletingLastPathComponent())
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.copyItem(at: source, to: destination)
        }
        for item in manifest.rolloutFirstLines {
            try RolloutRepairer.restore(url: URL(fileURLWithPath: item.originalPath), firstLine: item.firstLine)
        }
    }

    private func providerInfo(parsedConfig: ParsedConfig, configURL: URL) -> ProviderInfo {
        let provider = parsedConfig.rootValues["model_provider"].flatMap { $0.isEmpty ? nil : $0 } ?? "openai"
        let section = parsedConfig.providerSections[provider] ?? [:]
        let authLabel: String
        if provider == "openai" {
            authLabel = section["requires_openai_auth"] == "false" ? "OpenAI API Key" : "OpenAI OAuth"
        } else if section["requires_openai_auth"] == "true" {
            authLabel = "第三方 API"
        } else {
            authLabel = "自定义 Provider"
        }
        return ProviderInfo(provider: provider, authLabel: authLabel, configURL: configURL)
    }

    private func latestStateDatabase(in sqliteHome: URL) -> StateDatabase? {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: sqliteHome, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return nil
        }
        let states = files.filter { $0.lastPathComponent.hasPrefix("state_") && $0.pathExtension == "sqlite" }
        return states.compactMap { url in
            let modifiedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return StateDatabase(url: url, modifiedAt: modifiedAt)
        }
        .sorted { $0.modifiedAt > $1.modifiedAt }
        .first
    }

    private func missingIndexRepairs(codexHome: URL, threads: [ThreadRow]) -> [IndexRepair] {
        let indexURL = codexHome.appendingPathComponent("session_index.jsonl")
        let existing = existingIndexIDs(indexURL: indexURL)
        return threads
            .filter { !existing.contains($0.id) }
            .map { IndexRepair(threadID: $0.id, title: $0.title, updatedAt: $0.updatedAt) }
    }

    private func existingIndexIDs(indexURL: URL) -> Set<String> {
        guard let content = try? String(contentsOf: indexURL, encoding: .utf8) else { return [] }
        var ids = Set<String>()
        for line in content.components(separatedBy: .newlines) where !line.isEmpty {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = object["id"] as? String else { continue }
            ids.insert(id)
        }
        return ids
    }

    private func appendMissingIndexEntries(_ repairs: [IndexRepair], codexHome: URL) throws {
        guard !repairs.isEmpty else { return }
        let indexURL = codexHome.appendingPathComponent("session_index.jsonl")
        if !FileManager.default.fileExists(atPath: indexURL.path) {
            FileManager.default.createFile(atPath: indexURL.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: indexURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        for repair in repairs {
            let object: [String: Any] = [
                "id": repair.threadID,
                "thread_name": repair.title,
                "updated_at": ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: TimeInterval(repair.updatedAt)))
            ]
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            handle.write(data)
            handle.write(Data("\n".utf8))
        }
    }
}

struct BackupManifest: Codable {
    struct FileItem: Codable {
        var originalPath: String
        var backupRelativePath: String
    }

    struct FirstLineItem: Codable {
        var originalPath: String
        var firstLine: String
    }

    var record: BackupRecord
    var files: [FileItem]
    var rolloutFirstLines: [FirstLineItem]
}

extension JSONEncoder {
    static var codexSynced: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var codexSynced: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
