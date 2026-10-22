import Foundation
import SQLite3

final class SQLiteStore: StateStore {
    private var connection: OpaquePointer?
    let url: URL
    init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if let connection { sqlite3_close(connection) }; connection = nil
            throw DomainError.invalid("Cannot open local database. Original file preserved at \(url.path).")
        }
        do {
            try execute("PRAGMA journal_mode=WAL;")
            try execute("PRAGMA synchronous=FULL;")
            try execute("PRAGMA busy_timeout=3000;")
            let version = try scalar("PRAGMA user_version;")
            guard version <= 1 else { throw DomainError.invalid("Database was created by a newer app. Original preserved.") }
            if version == 0 {
                try execute("BEGIN IMMEDIATE;")
                do {
                    try execute("CREATE TABLE IF NOT EXISTS app_state (id INTEGER PRIMARY KEY CHECK(id=1), payload BLOB NOT NULL);")
                    try execute("PRAGMA user_version=1;")
                    try execute("COMMIT;")
                } catch { try? execute("ROLLBACK;"); throw error }
            }
            guard try textScalar("PRAGMA quick_check;") == "ok" else { throw DomainError.invalid("Database integrity check failed. Original preserved; use recovery in the app.") }
        } catch { sqlite3_close(connection); connection = nil; throw error }
    }
    deinit { sqlite3_close(connection) }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }
    private func failure() -> Error { DomainError.invalid("Storage operation failed (SQLite \(sqlite3_errcode(connection))). Action was not saved; retry or recover the database.") }
    private func scalar(_ sql: String) throws -> Int {
        var statement: OpaquePointer?; defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, sqlite3_step(statement) == SQLITE_ROW else { throw failure() }
        return Int(sqlite3_column_int(statement, 0))
    }
    private func textScalar(_ sql: String) throws -> String {
        var statement: OpaquePointer?; defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, sqlite3_step(statement) == SQLITE_ROW, let chars = sqlite3_column_text(statement, 0) else { throw failure() }
        return String(cString: chars)
    }
    func load() throws -> Database {
        var statement: OpaquePointer?; defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(connection, "SELECT payload FROM app_state WHERE id=1", -1, &statement, nil) == SQLITE_OK else { throw failure() }
        let status = sqlite3_step(statement)
        if status == SQLITE_DONE { return Database() }
        guard status == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else { throw failure() }
        let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
        do {
            let db = try JSONDecoder().decode(Database.self, from: data)
            guard db.version == 1 else { throw DomainError.invalid("Unsupported state version.") }
            return db
        } catch { throw DomainError.invalid("Saved state could not be decoded. Original preserved. Recover/reset through Settings.") }
    }
    func save(_ database: Database) throws {
        let data = try JSONEncoder().encode(database)
        try execute("BEGIN IMMEDIATE;")
        do {
            var statement: OpaquePointer?; defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(connection, "INSERT INTO app_state(id,payload) VALUES(1,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload", -1, &statement, nil) == SQLITE_OK else { throw failure() }
            let result = data.withUnsafeBytes { bytes in
                sqlite3_bind_blob(statement, 1, bytes.baseAddress, Int32(data.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
            guard result == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
            try execute("COMMIT;")
        } catch { try? execute("ROLLBACK;"); throw error }
    }
}
