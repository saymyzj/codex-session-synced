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
        let sql = """
        SELECT id, rollout_path, title, model_provider, has_user_event, cwd, thread_source, archived, updated_at
        FROM threads
        ORDER BY updated_at DESC
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
                threadSource: nullableText(statement, 6),
                archived: sqlite3_column_int(statement, 7) != 0,
                updatedAt: sqlite3_column_int64(statement, 8)
            ))
        }
        return rows
    }

    func updateProvider(threadIDs: [String], provider: String) throws {
        guard !threadIDs.isEmpty else { return }
        try execute("BEGIN IMMEDIATE")
        do {
            let sql = "UPDATE threads SET model_provider = ? WHERE id = ?"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SQLiteError.prepareFailed(errorMessage)
            }
            defer { sqlite3_finalize(statement) }

            for id in threadIDs {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                bind(provider, to: statement, index: 1)
                bind(id, to: statement, index: 2)
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

    private func text(_ statement: OpaquePointer?, _ index: Int32) -> String {
        nullableText(statement, index) ?? ""
    }

    private func nullableText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: cString)
    }

    private func bind(_ value: String, to statement: OpaquePointer?, index: Int32) {
        sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
