import Foundation
import SQLite3

/// Moves data that older versions scattered across Documents and Application Support into `data/`.
/// Runs once at launch, before any database opens. Nothing is overwritten: if the new location
/// already holds a file, the old one is left where it was.
enum LegacyDataMigration {
    static func run(home: YisiHome = .shared,
                    documents: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0],
                    support: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]) {
        let manager = FileManager.default
        try? manager.createDirectory(at: home.data, withIntermediateDirectories: true)

        move(documents.appendingPathComponent("YisiHistory.sqlite"), to: home.historyDatabase, sidecars: true)
        move(documents.appendingPathComponent("HistoryImages", isDirectory: true),
             to: home.data.appendingPathComponent("HistoryImages", isDirectory: true))
        move(support.appendingPathComponent("com.yisi.app/learned_rules.db"), to: home.learnedRulesDatabase, sidecars: true)
    }

    private static func move(_ source: URL, to destination: URL, sidecars: Bool = false) {
        let manager = FileManager.default
        guard manager.fileExists(atPath: source.path), !manager.fileExists(atPath: destination.path) else { return }
        do {
            try manager.moveItem(at: source, to: destination)
            if sidecars {
                for suffix in ["-wal", "-shm"] {
                    let from = URL(fileURLWithPath: source.path + suffix)
                    if manager.fileExists(atPath: from.path) {
                        try? manager.moveItem(at: from, to: URL(fileURLWithPath: destination.path + suffix))
                    }
                }
            }
        } catch {
            NSLog("Yisi could not move %@: %@", source.path, error.localizedDescription)
        }
    }
}

enum SQLiteBackup {
    static func vacuum(_ db: OpaquePointer?, into url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        let path = url.path.replacingOccurrences(of: "'", with: "''")
        guard let db, sqlite3_exec(db, "VACUUM INTO '\(path)'", nil, nil, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "database is not open"
            throw NSError(domain: "YisiData", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}
