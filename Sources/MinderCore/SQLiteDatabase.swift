import CSQLite
import Foundation

enum SQLiteError: Error, LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case bindFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let message): return "SQLite open failed: \(message)"
        case .prepareFailed(let message): return "SQLite prepare failed: \(message)"
        case .stepFailed(let message): return "SQLite step failed: \(message)"
        case .bindFailed(let message): return "SQLite bind failed: \(message)"
        }
    }
}

enum SQLiteValue {
    case null
    case text(String)
    case int(Int)
    case double(Double)
    case blob(Data)
}

final class SQLiteDatabase {
    private var handle: OpaquePointer?

    init(url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var database: OpaquePointer?
        if sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            sqlite3_close(database)
            throw SQLiteError.openFailed(message)
        }

        handle = database
        try execute("PRAGMA foreign_keys = ON")
        try execute("PRAGMA journal_mode = WAL")
    }

    deinit {
        sqlite3_close(handle)
    }

    func execute(_ sql: String, _ values: [SQLiteValue] = []) throws {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }

        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            throw SQLiteError.stepFailed(lastErrorMessage)
        }
    }

    func query(_ sql: String, _ values: [SQLiteValue] = []) throws -> [[String: String?]] {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }

        var rows: [[String: String?]] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                return rows
            }
            guard result == SQLITE_ROW else {
                throw SQLiteError.stepFailed(lastErrorMessage)
            }

            var row: [String: String?] = [:]
            for column in 0..<sqlite3_column_count(statement) {
                guard let name = sqlite3_column_name(statement, column) else { continue }
                let key = String(cString: name)
                if sqlite3_column_type(statement, column) == SQLITE_NULL {
                    row[key] = nil
                } else if let text = sqlite3_column_text(statement, column) {
                    row[key] = String(cString: text)
                } else {
                    row[key] = nil
                }
            }
            rows.append(row)
        }
    }

    func transaction<T>(_ work: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            let value = try work()
            try execute("COMMIT")
            return value
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func prepare(_ sql: String, _ values: [SQLiteValue]) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(handle, sql, -1, &statement, nil) != SQLITE_OK {
            throw SQLiteError.prepareFailed(lastErrorMessage)
        }

        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            let result: Int32
            switch value {
            case .null:
                result = sqlite3_bind_null(statement, position)
            case .text(let string):
                result = sqlite3_bind_text(statement, position, string, -1, SQLITE_TRANSIENT)
            case .int(let int):
                result = sqlite3_bind_int64(statement, position, sqlite3_int64(int))
            case .double(let double):
                result = sqlite3_bind_double(statement, position, double)
            case .blob(let data):
                result = data.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(statement, position, bytes.baseAddress, Int32(data.count), SQLITE_TRANSIENT)
                }
            }

            if result != SQLITE_OK {
                throw SQLiteError.bindFailed(lastErrorMessage)
            }
        }

        return statement
    }

    private var lastErrorMessage: String {
        guard let handle else { return "Database handle is closed" }
        return String(cString: sqlite3_errmsg(handle))
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
