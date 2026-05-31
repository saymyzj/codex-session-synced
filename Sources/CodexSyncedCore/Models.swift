import Foundation

public enum Language: String, CaseIterable, Identifiable {
    case zh
    case en

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .zh: "中文"
        case .en: "English"
        }
    }
}

public enum BackupMode: String, CaseIterable, Identifiable, Codable {
    case lightweight
    case full

    public var id: String { rawValue }

    public var zhTitle: String {
        switch self {
        case .lightweight: "轻简备份"
        case .full: "全量备份"
        }
    }

    public var enTitle: String {
        switch self {
        case .lightweight: "Lightweight"
        case .full: "Full"
        }
    }
}

public enum ScanStatus: Equatable {
    case idle
    case scanning
    case ready
    case repairing(String)
    case success(String)
    case failed(String)
}

public struct AppSettings {
    public var language: Language
    public var codexHome: URL
    public var sqliteHome: URL?
    public var defaultBackupMode: BackupMode
    public var lightweightLimit: Int
    public var fullLimit: Int
    public var openCodexAfterRepair: Bool

    public init(language: Language, codexHome: URL, sqliteHome: URL?, defaultBackupMode: BackupMode, lightweightLimit: Int, fullLimit: Int, openCodexAfterRepair: Bool) {
        self.language = language
        self.codexHome = codexHome
        self.sqliteHome = sqliteHome
        self.defaultBackupMode = defaultBackupMode
        self.lightweightLimit = lightweightLimit
        self.fullLimit = fullLimit
        self.openCodexAfterRepair = openCodexAfterRepair
    }

    public static func load() -> AppSettings {
        let defaults = UserDefaults.standard
        let home = FileManager.default.homeDirectoryForCurrentUser
        let env = ProcessInfo.processInfo.environment
        let codexHomePath = defaults.string(forKey: "codexHome")
            ?? env["CODEX_HOME"]
            ?? home.appendingPathComponent(".codex").path
        let sqliteHomePath = defaults.string(forKey: "sqliteHome")
            ?? env["CODEX_SQLITE_HOME"]
        let language = Language(rawValue: defaults.string(forKey: "language") ?? "zh") ?? .zh
        let backupMode = BackupMode(rawValue: defaults.string(forKey: "defaultBackupMode") ?? "lightweight") ?? .lightweight

        return AppSettings(
            language: language,
            codexHome: URL(fileURLWithPath: codexHomePath).standardizedFileURL,
            sqliteHome: sqliteHomePath.map { URL(fileURLWithPath: $0).standardizedFileURL },
            defaultBackupMode: backupMode,
            lightweightLimit: max(defaults.integer(forKey: "lightweightLimit"), 5),
            fullLimit: max(defaults.integer(forKey: "fullLimit"), 3),
            openCodexAfterRepair: defaults.object(forKey: "openCodexAfterRepair") as? Bool ?? true
        )
    }

    public func save() {
        let defaults = UserDefaults.standard
        defaults.set(language.rawValue, forKey: "language")
        defaults.set(codexHome.path, forKey: "codexHome")
        defaults.set(sqliteHome?.path, forKey: "sqliteHome")
        defaults.set(defaultBackupMode.rawValue, forKey: "defaultBackupMode")
        defaults.set(lightweightLimit, forKey: "lightweightLimit")
        defaults.set(fullLimit, forKey: "fullLimit")
        defaults.set(openCodexAfterRepair, forKey: "openCodexAfterRepair")
    }
}

public struct ProviderInfo: Equatable {
    public var provider: String
    public var authLabel: String
    public var configURL: URL

    public init(provider: String, authLabel: String, configURL: URL) {
        self.provider = provider
        self.authLabel = authLabel
        self.configURL = configURL
    }
}

public struct StateDatabase: Identifiable, Equatable {
    public var id: String { url.path }
    public var url: URL
    public var modifiedAt: Date

    public init(url: URL, modifiedAt: Date) {
        self.url = url
        self.modifiedAt = modifiedAt
    }
}

public struct ThreadRow: Identifiable, Equatable, Codable {
    public var id: String
    public var rolloutPath: String
    public var title: String
    public var modelProvider: String
    public var hasUserEvent: Bool
    public var cwd: String
    public var threadSource: String?
    public var archived: Bool
    public var updatedAt: Int64

    public init(id: String, rolloutPath: String, title: String, modelProvider: String, hasUserEvent: Bool, cwd: String, threadSource: String?, archived: Bool, updatedAt: Int64) {
        self.id = id
        self.rolloutPath = rolloutPath
        self.title = title
        self.modelProvider = modelProvider
        self.hasUserEvent = hasUserEvent
        self.cwd = cwd
        self.threadSource = threadSource
        self.archived = archived
        self.updatedAt = updatedAt
    }
}

public struct RolloutRepair: Identifiable, Equatable, Codable {
    public var id: String
    public var url: URL
    public var sessionID: String
    public var currentProvider: String?
    public var targetProvider: String
    public var originalFirstLine: String
    public var repairedFirstLine: String

    public init(id: String, url: URL, sessionID: String, currentProvider: String?, targetProvider: String, originalFirstLine: String, repairedFirstLine: String) {
        self.id = id
        self.url = url
        self.sessionID = sessionID
        self.currentProvider = currentProvider
        self.targetProvider = targetProvider
        self.originalFirstLine = originalFirstLine
        self.repairedFirstLine = repairedFirstLine
    }
}

public struct IndexRepair: Identifiable, Equatable, Codable {
    public var id: String
    public var threadID: String
    public var title: String
    public var updatedAt: Int64

    public init(threadID: String, title: String, updatedAt: Int64) {
        self.id = threadID
        self.threadID = threadID
        self.title = title
        self.updatedAt = updatedAt
    }
}

public struct ScanResult: Equatable {
    public var providerInfo: ProviderInfo
    public var stateDatabase: StateDatabase?
    public var threads: [ThreadRow]
    public var sqliteProviderUpdates: [ThreadRow]
    public var sqliteCompatibilityUpdates: [ThreadRow]
    public var rolloutRepairs: [RolloutRepair]
    public var indexRepairs: [IndexRepair]
    public var backups: [BackupRecord]
    public var codexHome: URL
    public var sqliteHome: URL
    public var lastRepairAt: Date?

    public var hasRepairs: Bool {
        !sqliteProviderUpdates.isEmpty || !sqliteCompatibilityUpdates.isEmpty || !rolloutRepairs.isEmpty || !indexRepairs.isEmpty
    }

    public init(providerInfo: ProviderInfo, stateDatabase: StateDatabase?, threads: [ThreadRow], sqliteProviderUpdates: [ThreadRow], sqliteCompatibilityUpdates: [ThreadRow], rolloutRepairs: [RolloutRepair], indexRepairs: [IndexRepair], backups: [BackupRecord], codexHome: URL, sqliteHome: URL, lastRepairAt: Date?) {
        self.providerInfo = providerInfo
        self.stateDatabase = stateDatabase
        self.threads = threads
        self.sqliteProviderUpdates = sqliteProviderUpdates
        self.sqliteCompatibilityUpdates = sqliteCompatibilityUpdates
        self.rolloutRepairs = rolloutRepairs
        self.indexRepairs = indexRepairs
        self.backups = backups
        self.codexHome = codexHome
        self.sqliteHome = sqliteHome
        self.lastRepairAt = lastRepairAt
    }
}

public struct RepairSummary: Codable, Equatable {
    public var targetProvider: String
    public var sqliteProviderUpdates: Int
    public var sqliteCompatibilityUpdates: Int
    public var rolloutUpdates: Int
    public var indexInsertions: Int
    public var repairedAt: Date

    public init(targetProvider: String, sqliteProviderUpdates: Int, sqliteCompatibilityUpdates: Int, rolloutUpdates: Int, indexInsertions: Int, repairedAt: Date) {
        self.targetProvider = targetProvider
        self.sqliteProviderUpdates = sqliteProviderUpdates
        self.sqliteCompatibilityUpdates = sqliteCompatibilityUpdates
        self.rolloutUpdates = rolloutUpdates
        self.indexInsertions = indexInsertions
        self.repairedAt = repairedAt
    }
}

public struct BackupRecord: Identifiable, Codable, Equatable {
    public var id: String { directoryName }
    public var directoryName: String
    public var createdAt: Date
    public var mode: BackupMode
    public var targetProvider: String
    public var summary: RepairSummary
    public var sizeBytes: Int64
    public var path: String

    public init(directoryName: String, createdAt: Date, mode: BackupMode, targetProvider: String, summary: RepairSummary, sizeBytes: Int64, path: String) {
        self.directoryName = directoryName
        self.createdAt = createdAt
        self.mode = mode
        self.targetProvider = targetProvider
        self.summary = summary
        self.sizeBytes = sizeBytes
        self.path = path
    }
}
