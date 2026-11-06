import Foundation
import SQLite3

class DatabaseManager {
    static let shared = DatabaseManager()
    private var db: OpaquePointer?
    
    // 串行队列保护 SQLite 访问（SQLite 默认不是线程安全的）
    private let dbQueue = DispatchQueue(label: "com.yisi.database", qos: .userInitiated)
    
    private init() {
        dbQueue.sync {
            openDatabase()
            createTable()
            migrateDatabase()
        }
    }
    
    private func getDatabasePath() -> String {
        try? FileManager.default.createDirectory(at: YisiHome.shared.data, withIntermediateDirectories: true)
        return YisiHome.shared.historyDatabase.path
    }
    
    private func openDatabase() {
        let dbPath = getDatabasePath()
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("Error opening database")
        }
    }
    
    private func createTable() {
        let createTableString = """
        CREATE TABLE IF NOT EXISTS translation_history(
        id TEXT PRIMARY KEY,
        sourceText TEXT,
        targetText TEXT,
        sourceLanguage TEXT,
        targetLanguage TEXT,
        timestamp REAL,
        type TEXT,
        presetName TEXT,
        customPrompt TEXT,
        imagePath TEXT
        );
        """
        
        var createTableStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, createTableString, -1, &createTableStatement, nil) == SQLITE_OK {
            if sqlite3_step(createTableStatement) == SQLITE_DONE {
                print("Translation history table created.")
            } else {
                print("Translation history table could not be created.")
            }
        } else {
            print("CREATE TABLE statement could not be prepared.")
        }
        sqlite3_finalize(createTableStatement)
    }
    
    /// 执行数据库迁移，为现有表添加新字段
    private func migrateDatabase() {
        // 检查 imagePath 字段是否存在，不存在则添加
        let alterSQL = "ALTER TABLE translation_history ADD COLUMN imagePath TEXT;"
        var statement: OpaquePointer?
        
        // ALTER TABLE 会失败如果字段已存在，这是预期行为
        if sqlite3_prepare_v2(db, alterSQL, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_DONE {
                print("Database migrated: added imagePath column.")
            }
        }
        sqlite3_finalize(statement)
    }
    
    /// A consistent copy for export, taken through the open connection.
    func backup(to url: URL) throws {
        try dbQueue.sync { try SQLiteBackup.vacuum(db, into: url) }
    }

    func insert(item: TranslationHistoryItem) {
        dbQueue.async { [weak self] in
            self?.insertInternal(item: item)
        }
    }
    
    private func insertInternal(item: TranslationHistoryItem) {
        let insertStatementString = "INSERT INTO translation_history (id, sourceText, targetText, sourceLanguage, targetLanguage, timestamp, type, presetName, customPrompt, imagePath) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);"
        var insertStatement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, insertStatementString, -1, &insertStatement, nil) == SQLITE_OK {
            let idString = item.id.uuidString as NSString
            let sourceText = item.sourceText as NSString
            let targetText = item.targetText as NSString
            let sourceLanguage = item.sourceLanguage as NSString
            let targetLanguage = item.targetLanguage as NSString
            let timestamp = item.timestamp.timeIntervalSince1970
            let type = item.type.rawValue as NSString
            let presetName = (item.presetName ?? "") as NSString
            let customPrompt = (item.customPrompt ?? "") as NSString
            let imagePath = (item.imagePath ?? "") as NSString
            
            sqlite3_bind_text(insertStatement, 1, idString.utf8String, -1, nil)
            sqlite3_bind_text(insertStatement, 2, sourceText.utf8String, -1, nil)
            sqlite3_bind_text(insertStatement, 3, targetText.utf8String, -1, nil)
            sqlite3_bind_text(insertStatement, 4, sourceLanguage.utf8String, -1, nil)
            sqlite3_bind_text(insertStatement, 5, targetLanguage.utf8String, -1, nil)
            sqlite3_bind_double(insertStatement, 6, timestamp)
            sqlite3_bind_text(insertStatement, 7, type.utf8String, -1, nil)
            sqlite3_bind_text(insertStatement, 8, presetName.utf8String, -1, nil)
            sqlite3_bind_text(insertStatement, 9, customPrompt.utf8String, -1, nil)
            sqlite3_bind_text(insertStatement, 10, imagePath.utf8String, -1, nil)
            
            if sqlite3_step(insertStatement) == SQLITE_DONE {
                print("Successfully inserted row.")
            } else {
                print("Could not insert row.")
            }
        } else {
            print("INSERT statement could not be prepared.")
        }
        sqlite3_finalize(insertStatement)
    }
    
    func fetchAll() -> [TranslationHistoryItem] {
        return dbQueue.sync {
            fetchAllInternal()
        }
    }
    
    private func fetchAllInternal() -> [TranslationHistoryItem] {
        let queryStatementString = "SELECT * FROM translation_history ORDER BY timestamp DESC;"
        var queryStatement: OpaquePointer?
        var items: [TranslationHistoryItem] = []
        
        if sqlite3_prepare_v2(db, queryStatementString, -1, &queryStatement, nil) == SQLITE_OK {
            while sqlite3_step(queryStatement) == SQLITE_ROW {
                let idString = String(cString: sqlite3_column_text(queryStatement, 0))
                let sourceText = String(cString: sqlite3_column_text(queryStatement, 1))
                let targetText = String(cString: sqlite3_column_text(queryStatement, 2))
                let sourceLanguage = String(cString: sqlite3_column_text(queryStatement, 3))
                let targetLanguage = String(cString: sqlite3_column_text(queryStatement, 4))
                let timestamp = sqlite3_column_double(queryStatement, 5)
                let typeString = String(cString: sqlite3_column_text(queryStatement, 6))
                
                // Handle nullable fields
                var presetName: String? = nil
                if let cString = sqlite3_column_text(queryStatement, 7) {
                    presetName = String(cString: cString)
                    if presetName?.isEmpty == true { presetName = nil }
                }
                
                var customPrompt: String? = nil
                if let cString = sqlite3_column_text(queryStatement, 8) {
                    customPrompt = String(cString: cString)
                    if customPrompt?.isEmpty == true { customPrompt = nil }
                }
                
                var imagePath: String? = nil
                if let cString = sqlite3_column_text(queryStatement, 9) {
                    imagePath = String(cString: cString)
                    if imagePath?.isEmpty == true { imagePath = nil }
                }
                
                if let id = UUID(uuidString: idString),
                   let type = HistoryType(rawValue: typeString) {
                    let item = TranslationHistoryItem(
                        id: id,
                        sourceText: sourceText,
                        targetText: targetText,
                        sourceLanguage: sourceLanguage,
                        targetLanguage: targetLanguage,
                        timestamp: Date(timeIntervalSince1970: timestamp),
                        type: type,
                        presetName: presetName,
                        customPrompt: customPrompt,
                        imagePath: imagePath
                    )
                    items.append(item)
                }
            }
        } else {
            print("SELECT statement could not be prepared")
        }
        sqlite3_finalize(queryStatement)
        return items
    }
    
    func delete(id: UUID) {
        dbQueue.async { [weak self] in
            self?.deleteInternal(id: id)
        }
    }
    
    private func deleteInternal(id: UUID) {
        let deleteStatementString = "DELETE FROM translation_history WHERE id = ?;"
        var deleteStatement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, deleteStatementString, -1, &deleteStatement, nil) == SQLITE_OK {
            let idString = id.uuidString as NSString
            sqlite3_bind_text(deleteStatement, 1, idString.utf8String, -1, nil)
            
            if sqlite3_step(deleteStatement) == SQLITE_DONE {
                print("Successfully deleted row.")
            } else {
                print("Could not delete row.")
            }
        } else {
            print("DELETE statement could not be prepared")
        }
        sqlite3_finalize(deleteStatement)
    }
    
    func clearAll() {
        dbQueue.async { [weak self] in
            self?.clearAllInternal()
        }
    }
    
    private func clearAllInternal() {
        let deleteStatementString = "DELETE FROM translation_history;"
        var deleteStatement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, deleteStatementString, -1, &deleteStatement, nil) == SQLITE_OK {
            if sqlite3_step(deleteStatement) == SQLITE_DONE {
                print("Successfully cleared all rows.")
            } else {
                print("Could not clear rows.")
            }
        } else {
            print("DELETE ALL statement could not be prepared")
        }
        sqlite3_finalize(deleteStatement)
    }
    
    deinit {
        sqlite3_close(db)
    }
}
