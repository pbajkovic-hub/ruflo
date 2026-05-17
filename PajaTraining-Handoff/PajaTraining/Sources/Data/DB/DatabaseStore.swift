import Foundation
import GRDB

final class DatabaseStore {
    private(set) var pool: DatabasePool?

    func setup() async throws {
        let url = try databaseURL()
        var config = Configuration()
        config.prepareDatabase { db in
            db.trace { print("[GRDB] \($0)") }
        }
        let p = try DatabasePool(path: url.path, configuration: config)
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            guard let schemaURL = Bundle.main.url(forResource: "schema_v1", withExtension: "sql"),
                  let sql = try? String(contentsOf: schemaURL, encoding: .utf8)
            else { throw DatabaseStoreError.schemaMissing }
            // Execute the SQL in chunks split by semicolons (GRDB execute(sql:) handles batches)
            try db.execute(sql: sql)
        }
        try migrator.migrate(p)
        pool = p
    }

    private func databaseURL() throws -> URL {
        // Prefer iCloud Documents container for cross-device sync.
        if let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
            let dir = container.appendingPathComponent("Documents", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir.appendingPathComponent("paja.db")
        }
        let docs = try FileManager.default.url(for: .documentDirectory,
                                               in: .userDomainMask,
                                               appropriateFor: nil,
                                               create: true)
        return docs.appendingPathComponent("paja.db")
    }

    // MARK: - Access helpers

    func read<T>(_ block: @escaping (Database) throws -> T) async throws -> T {
        guard let pool else { throw DatabaseStoreError.notSetup }
        return try await pool.read(block)
    }

    func write<T>(_ block: @escaping (Database) throws -> T) async throws -> T {
        guard let pool else { throw DatabaseStoreError.notSetup }
        return try await pool.write(block)
    }

    /// Synchronous read — only call from non-actor, non-main contexts (e.g. DailyLogStore protocol).
    func syncRead<T>(_ block: (Database) throws -> T) throws -> T {
        guard let pool else { throw DatabaseStoreError.notSetup }
        return try pool.read(block)
    }

    func syncWrite<T>(_ block: (Database) throws -> T) throws -> T {
        guard let pool else { throw DatabaseStoreError.notSetup }
        return try pool.write(block)
    }
}

enum DatabaseStoreError: Error {
    case notSetup
    case schemaMissing
}
