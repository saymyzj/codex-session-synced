import Foundation

extension CodexRepairService {
    func loadBackups(codexHome: URL) -> [BackupRecord] {
        let root = backupRoot(codexHome: codexHome)
        guard let directories = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }
        return directories.compactMap { directory in
            let manifestURL = directory.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? JSONDecoder.codexSynced.decode(BackupManifest.self, from: data) else {
                return nil
            }
            var record = manifest.record
            record.sizeBytes = FileUtilities.directorySize(directory)
            record.path = directory.path
            return record
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    func createBackup(scan: ScanResult, settings: AppSettings, mode: BackupMode) throws -> BackupRecord {
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let directoryName = "\(mode.rawValue)-\(formatter.string(from: now))"
        let directory = backupRoot(codexHome: scan.codexHome).appendingPathComponent(directoryName)
        try FileUtilities.ensureDirectory(directory)

        let summary = RepairSummary(
            targetProvider: scan.providerInfo.provider,
            sqliteProviderUpdates: scan.sqliteProviderUpdates.count,
            sqliteCompatibilityUpdates: scan.sqliteCompatibilityUpdates.count,
            rolloutUpdates: scan.rolloutRepairs.count,
            indexInsertions: scan.indexRepairs.count,
            repairedAt: now
        )

        var files: [BackupManifest.FileItem] = []
        func copy(_ url: URL, relative: String) throws {
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            let destination = directory.appendingPathComponent(relative)
            try FileUtilities.ensureDirectory(destination.deletingLastPathComponent())
            try FileUtilities.copyIfExists(url, to: destination)
            files.append(.init(originalPath: url.path, backupRelativePath: relative))
        }

        if let stateURL = scan.stateDatabase?.url {
            try copy(stateURL, relative: "sqlite/\(stateURL.lastPathComponent)")
            try copy(URL(fileURLWithPath: stateURL.path + "-wal"), relative: "sqlite/\(stateURL.lastPathComponent)-wal")
            try copy(URL(fileURLWithPath: stateURL.path + "-shm"), relative: "sqlite/\(stateURL.lastPathComponent)-shm")
        }
        try copy(scan.codexHome.appendingPathComponent("config.toml"), relative: "codex/config.toml")
        try copy(scan.codexHome.appendingPathComponent("session_index.jsonl"), relative: "codex/session_index.jsonl")
        try copy(scan.codexHome.appendingPathComponent(".codex-global-state.json"), relative: "codex/.codex-global-state.json")

        if mode == .full {
            try copyDirectoryIfExists(scan.codexHome.appendingPathComponent("sessions"), to: directory.appendingPathComponent("codex/sessions"))
            try copyDirectoryIfExists(scan.codexHome.appendingPathComponent("archived_sessions"), to: directory.appendingPathComponent("codex/archived_sessions"))
        }

        let firstLines = scan.rolloutRepairs.map {
            BackupManifest.FirstLineItem(originalPath: $0.url.path, firstLine: $0.originalFirstLine)
        }
        let record = BackupRecord(
            directoryName: directoryName,
            createdAt: now,
            mode: mode,
            targetProvider: scan.providerInfo.provider,
            summary: summary,
            sizeBytes: 0,
            path: directory.path
        )
        let manifest = BackupManifest(record: record, files: files, rolloutFirstLines: firstLines)
        let manifestData = try JSONEncoder.codexSynced.encode(manifest)
        try manifestData.write(to: directory.appendingPathComponent("manifest.json"))

        var finalRecord = record
        finalRecord.sizeBytes = FileUtilities.directorySize(directory)
        let finalManifest = BackupManifest(record: finalRecord, files: files, rolloutFirstLines: firstLines)
        try JSONEncoder.codexSynced.encode(finalManifest).write(to: directory.appendingPathComponent("manifest.json"))
        return finalRecord
    }

    func rotateBackups(codexHome: URL, mode: BackupMode, limit: Int) throws {
        let backups = loadBackups(codexHome: codexHome).filter { $0.mode == mode }.sorted { $0.createdAt > $1.createdAt }
        guard backups.count > limit else { return }
        for backup in backups.dropFirst(limit) {
            try FileManager.default.removeItem(at: URL(fileURLWithPath: backup.path))
        }
    }

    public func backupRoot(codexHome: URL) -> URL {
        codexHome.appendingPathComponent("codex-synced-backups", isDirectory: true)
    }

    private func copyDirectoryIfExists(_ source: URL, to destination: URL) throws {
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileUtilities.ensureDirectory(destination.deletingLastPathComponent())
        try FileManager.default.copyItem(at: source, to: destination)
    }
}
