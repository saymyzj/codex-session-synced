import Foundation
import SQLite3

enum SQLiteError: LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let message): "无法打开 SQLite：\(message)"
        case .prepareFailed(let message): "无法准备 SQLite 查询：\(message)"
        case .stepFailed(let message): "SQLite 执行失败：\(message)"
        }
    }
}

final class SQLiteDatabase {
    private var handle: OpaquePointer?

    init(path: String, readonly: Bool) throws {
        let flags = readonly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        if sqlite3_open_v2(path, &handle, flags, nil) != SQLITE_OK {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw SQLiteError.openFailed(message)
        }
    }

    deinit {
        sqlite3_close(handle)
    }

    func queryThreads() throws -> [ThreadRow] {
        let columns = try tableColumns("threads")
        let updatedAtMsExpression = columns.contains("updated_at_ms") ? "updated_at_ms" : "NULL"
        let sourceExpression = columns.contains("source") ? "source" : "''"
        let firstUserExpression = columns.contains("first_user_message") ? "first_user_message" : "''"
        let previewExpression = columns.contains("preview") ? "preview" : "''"
        let sql = """
        SELECT id, rollout_path, title, model_provider, has_user_event, cwd, thread_source, archived, updated_at,
               \(updatedAtMsExpression) AS updated_at_ms,
               \(sourceExpression) AS source,
               \(firstUserExpression) AS first_user_message,
               \(previewExpression) AS preview
        FROM threads
        ORDER BY COALESCE(NULLIF(\(updatedAtMsExpression), 0), updated_at * 1000) DESC
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteError.prepareFailed(errorMessage)
        }
        defer { sqlite3_finalize(statement) }

        var rows: [ThreadRow] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(ThreadRow(
                id: text(statement, 0),
                rolloutPath: text(statement, 1),
                title: text(statement, 2),
                modelProvider: text(statement, 3),
                hasUserEvent: sqlite3_column_int(statement, 4) != 0,
                cwd: text(statement, 5),
                source: text(statement, 10),
                threadSource: nullableText(statement, 6),
                archived: sqlite3_column_int(statement, 7) != 0,
                updatedAt: sqlite3_column_int64(statement, 8),
                updatedAtMs: nullableInt64(statement, 9),
                firstUserMessage: text(statement, 11),
                preview: text(statement, 12)
            ))
        }
        return rows
    }

    func updateProviders(_ repairs: [ProviderRepair]) throws {
        guard !repairs.isEmpty else { return }
        try execute("BEGIN IMMEDIATE")
        do {
            let sql = "UPDATE threads SET model_provider = ? WHERE id = ?"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SQLiteError.prepareFailed(errorMessage)
            }
            defer { sqlite3_finalize(statement) }

            for repair in repairs {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                bind(repair.targetProvider, to: statement, index: 1)
                bind(repair.thread.id, to: statement, index: 2)
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw SQLiteError.stepFailed(errorMessage)
                }
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func updateTimestamps(_ repairs: [TimestampRepair]) throws {
        guard !repairs.isEmpty else { return }
        let columns = try tableColumns("threads")
        let sql = columns.contains("updated_at_ms")
            ? "UPDATE threads SET updated_at = ?, updated_at_ms = ? WHERE id = ?"
            : "UPDATE threads SET updated_at = ? WHERE id = ?"

        try execute("BEGIN IMMEDIATE")
        do {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SQLiteError.prepareFailed(errorMessage)
            }
            defer { sqlite3_finalize(statement) }

            for repair in repairs {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                sqlite3_bind_int64(statement, 1, repair.targetUpdatedAtMs / 1000)
                if columns.contains("updated_at_ms") {
                    sqlite3_bind_int64(statement, 2, repair.targetUpdatedAtMs)
                    bind(repair.threadID, to: statement, index: 3)
                } else {
                    bind(repair.threadID, to: statement, index: 2)
                }
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw SQLiteError.stepFailed(errorMessage)
                }
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func updateTitles(_ repairs: [TitleRepair]) throws {
        guard !repairs.isEmpty else { return }
        try execute("BEGIN IMMEDIATE")
        do {
            let sql = "UPDATE threads SET title = ? WHERE id = ?"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SQLiteError.prepareFailed(errorMessage)
            }
            defer { sqlite3_finalize(statement) }

            for repair in repairs {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                bind(repair.targetTitle, to: statement, index: 1)
                bind(repair.threadID, to: statement, index: 2)
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw SQLiteError.stepFailed(errorMessage)
                }
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func updateCompatibility(threadIDs: [String]) throws {
        guard !threadIDs.isEmpty else { return }
        try execute("BEGIN IMMEDIATE")
        do {
            let sql = """
            UPDATE threads
            SET has_user_event = CASE WHEN has_user_event = 0 THEN 1 ELSE has_user_event END,
                cwd = CASE WHEN cwd = '' THEN '~' ELSE cwd END,
                thread_source = CASE WHEN thread_source IS NULL OR thread_source = '' THEN 'user' ELSE thread_source END
            WHERE id = ?
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SQLiteError.prepareFailed(errorMessage)
            }
            defer { sqlite3_finalize(statement) }

            for id in threadIDs {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                bind(id, to: statement, index: 1)
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw SQLiteError.stepFailed(errorMessage)
                }
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
            throw SQLiteError.stepFailed(errorMessage)
        }
    }

    private var errorMessage: String {
        handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
    }

    private func tableColumns(_ table: String) throws -> Set<String> {
        let sql = "PRAGMA table_info(\(table))"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteError.prepareFailed(errorMessage)
        }
        defer { sqlite3_finalize(statement) }

        var columns = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = nullableText(statement, 1) {
                columns.insert(name)
            }
        }
        return columns
    }

    private func text(_ statement: OpaquePointer?, _ index: Int32) -> String {
        nullableText(statement, index) ?? ""
    }

    private func nullableText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: cString)
    }

    private func nullableInt64(_ statement: OpaquePointer?, _ index: Int32) -> Int64? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_int64(statement, index)
    }

    private func bind(_ value: String, to statement: OpaquePointer?, index: Int32) {
        sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
