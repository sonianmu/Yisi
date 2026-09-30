import Foundation
import SQLite3

class LearningManager {
    static let shared = LearningManager()
    
    private var db: OpaquePointer?
    private let dbPath: String
    
    private init() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("com.yisi.app", isDirectory: true)
        
        // Create directory if needed
        try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)
        
        dbPath = appDir.appendingPathComponent("learned_rules.db").path
        openDatabase()
        createTableIfNeeded()
    }
    
    private func openDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("Error opening database")
        }
    }
    
    private func createTableIfNeeded() {
        let createTableQuery = """
        CREATE TABLE IF NOT EXISTS learned_rules (
            id TEXT PRIMARY KEY,
            original_text TEXT NOT NULL,
            ai_translation TEXT NOT NULL,
            user_correction TEXT NOT NULL,
            reasoning TEXT NOT NULL,
            rule_pattern TEXT NOT NULL,
            category TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            usage_count INTEGER DEFAULT 0
        );
        """
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, createTableQuery, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) != SQLITE_DONE {
                print("Error creating table")
            }
        }
        sqlite3_finalize(statement)
    }
    
    // MARK: - AI Analysis
    
    func analyzeCorrection(
        originalText: String,
        aiTranslation: String,
        userCorrection: String
    ) async throws -> UserLearnedRule {
        let analysisPrompt = generateAnalysisPrompt(
            originalText: originalText,
            aiTranslation: aiTranslation,
            userCorrection: userCorrection
        )
        
        // Call API
        let analysisJSON = try await AIService.shared.processAnalysis(analysisPrompt)
        
        // Clean and parse response
        let cleanedJSON = extractJSON(from: analysisJSON)
        guard let jsonData = cleanedJSON.data(using: .utf8) else {
            throw NSError(domain: "LearningError", code: 4, 
                         userInfo: [NSLocalizedDescriptionKey: "Invalid JSON encoding", "rawResponse": analysisJSON])
        }
        
        let analysis: RuleAnalysisResponse
        do {
            analysis = try JSONDecoder().decode(RuleAnalysisResponse.self, from: jsonData)
        } catch {
            print("❌ JSON Decoding Error:")
            print("  - Error: \(error)")
            print("  - Raw Response: \(analysisJSON)")
            print("  - Cleaned JSON: \(cleanedJSON)")
            throw NSError(domain: "LearningError", code: 5, 
                         userInfo: [NSLocalizedDescriptionKey: "JSON parsing failed: \(error.localizedDescription)", 
                                   "rawResponse": analysisJSON,
                                   "cleanedJSON": cleanedJSON])
        }
        
        // Create rule
        let categoryRaw = analysis.category
        // Map English category from AI to Chinese rawValue if needed, or use as is if it matches
        var category = RuleCategory(rawValue: categoryRaw)
        
        if category == nil {
            // Try mapping from English keys to Enum
            switch categoryRaw {
            case "attributeToVerb": category = .attributeToVerb
            case "metaphor": category = .metaphor
            case "terminology": category = .terminology
            case "style": category = .style
            default: category = .other
            }
        }
        
        let finalCategory = category ?? .other
        print("DEBUG: Rule Category - AI: \(categoryRaw) -> Final: \(finalCategory.rawValue)")
        
        let rule = UserLearnedRule(
            originalText: originalText,
            aiTranslation: aiTranslation,
            userCorrection: userCorrection,
            reasoning: analysis.reasoning,
            rulePattern: analysis.rulePattern,
            category: finalCategory
        )
        
        // Save to database
        print("DEBUG: Attempting to save rule to DB...")
        try saveRule(rule)
        print("DEBUG: Rule saved successfully! ID: \(rule.id)")
        
        return rule
    }
    
    // Helper to extract JSON from markdown code blocks
    private func extractJSON(from text: String) -> String {
        var jsonString = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove markdown code block if present
        if jsonString.hasPrefix("```json") {
            jsonString = jsonString.replacingOccurrences(of: "```json", with: "")
            jsonString = jsonString.replacingOccurrences(of: "```", with: "")
        } else if jsonString.hasPrefix("```") {
            jsonString = jsonString.replacingOccurrences(of: "```", with: "")
        }
        
        return jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func generateAnalysisPrompt(originalText: String, aiTranslation: String, userCorrection: String) -> String {
        return """
        You are analyzing why a user corrected an AI translation. Your task is to identify the user's intent.

        Original Text: "\(originalText)"
        AI Translation: "\(aiTranslation)"
        User Correction: "\(userCorrection)"

        Analyze the difference between AI Translation and User Correction. Output ONLY valid JSON:
        {
          "reasoning": "A single, concise sentence explaining why the user made this change.",
          "rulePattern": "",
          "category": "style"
        }
        
        RULES:
        - "reasoning" MUST be exactly ONE sentence, clear and actionable (e.g., "User prefers active voice over passive constructions.")
        - "rulePattern" can be empty (deprecated field)
        - "category" must be one of: attributeToVerb, metaphor, terminology, style, other
        - No markdown, no code blocks, just pure JSON
        """
    }

    
    // MARK: - Database Operations
    
    func saveRule(_ rule: UserLearnedRule) throws {
        print("DEBUG: saveRule called for rule: \(rule.id)")
        let insertQuery = """
        INSERT OR REPLACE INTO learned_rules 
        (id, original_text, ai_translation, user_correction, reasoning, rule_pattern, category, created_at, usage_count)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, insertQuery, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (rule.id.uuidString as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (rule.originalText as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 3, (rule.aiTranslation as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 4, (rule.userCorrection as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 5, (rule.reasoning as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 6, (rule.rulePattern as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 7, (rule.category.rawValue as NSString).utf8String, -1, nil)
            sqlite3_bind_int64(statement, 8, Int64(rule.createdAt.timeIntervalSince1970))
            sqlite3_bind_int(statement, 9, Int32(rule.usageCount))
            
            if sqlite3_step(statement) != SQLITE_DONE {
                let errorMsg = String(cString: sqlite3_errmsg(db))
                print("DEBUG: SQL Step Error: \(errorMsg)")
                sqlite3_finalize(statement)
                throw NSError(domain: "LearningError", code: 7, userInfo: [NSLocalizedDescriptionKey: "Failed to execute insert statement: \(errorMsg)"])
            }
        } else {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            print("DEBUG: SQL Prepare Error: \(errorMsg)")
            throw NSError(domain: "LearningError", code: 6, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare insert statement: \(errorMsg)"])
        }
        
        print("DEBUG: SQL Insert Successful")
        sqlite3_finalize(statement)
    }
    
    func getAllRules() -> [UserLearnedRule] {
        var rules: [UserLearnedRule] = []
        let query = "SELECT * FROM learned_rules ORDER BY created_at DESC;"
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                if let rule = parseRule(from: statement) {
                    rules.append(rule)
                }
            }
        }
        sqlite3_finalize(statement)
        return rules
    }
    
    func deleteRule(id: UUID) throws {
        let deleteQuery = "DELETE FROM learned_rules WHERE id = ?;"
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteQuery, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (id.uuidString as NSString).utf8String, -1, nil)
            if sqlite3_step(statement) != SQLITE_DONE {
                throw NSError(domain: "LearningError", code: 6, userInfo: [NSLocalizedDescriptionKey: "Failed to delete rule"])
            }
        }
        sqlite3_finalize(statement)
    }
    
    func updateRule(_ rule: UserLearnedRule) throws {
        // Use saveRule which does INSERT OR REPLACE
        try saveRule(rule)
        print("DEBUG: Rule updated successfully: \(rule.id)")
    }
    
    func addManualRule(
        reasoning: String,
        originalText: String = "",
        aiTranslation: String = "",
        userCorrection: String = "",
        category: RuleCategory = .other
    ) throws {
        let rule = UserLearnedRule(
            originalText: originalText,
            aiTranslation: aiTranslation,
            userCorrection: userCorrection,
            reasoning: reasoning,
            rulePattern: "",
            category: category
        )
        try saveRule(rule)
        print("DEBUG: Manual rule added: \(rule.id)")
    }

    
    private func parseRule(from statement: OpaquePointer?) -> UserLearnedRule? {
        guard let statement = statement else { return nil }
        
        let idString = String(cString: sqlite3_column_text(statement, 0))
        let originalText = String(cString: sqlite3_column_text(statement, 1))
        let aiTranslation = String(cString: sqlite3_column_text(statement, 2))
        let userCorrection = String(cString: sqlite3_column_text(statement, 3))
        let reasoning = String(cString: sqlite3_column_text(statement, 4))
        let rulePattern = String(cString: sqlite3_column_text(statement, 5))
        let categoryString = String(cString: sqlite3_column_text(statement, 6))
        let timestamp = sqlite3_column_int64(statement, 7)
        let usageCount = sqlite3_column_int(statement, 8)
        
        guard let id = UUID(uuidString: idString),
              let category = RuleCategory(rawValue: categoryString) else {
            return nil
        }
        
        return UserLearnedRule(
            id: id,
            originalText: originalText,
            aiTranslation: aiTranslation,
            userCorrection: userCorrection,
            reasoning: reasoning,
            rulePattern: rulePattern,
            category: category,
            createdAt: Date(timeIntervalSince1970: TimeInterval(timestamp)),
            usageCount: Int(usageCount)
        )
    }
    
    deinit {
        sqlite3_close(db)
    }
}
