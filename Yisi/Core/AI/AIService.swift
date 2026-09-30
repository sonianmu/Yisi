import Foundation
import AppKit

enum APIProvider: String {
    case openai = "OpenAI"
    case gemini = "Gemini"
    case zhipu = "Zhipu AI"
    case minimax = "MiniMax"
    case deepseek = "DeepSeek"
    case custom = "Custom Service"
}

class AIService: ObservableObject {
    static let shared = AIService()
    
    private init() {}
    
    // MARK: - Provider Factory
    
    /// 获取对应 API 提供商的 Provider 实例
    private func getProviderInstance(for provider: APIProvider) -> AIProvider {
        switch provider {
        case .gemini:
            return GeminiProvider()
        case .openai:
            return OpenAIProvider()
        case .zhipu:
            return ZhipuProvider()
        case .minimax:
            return MiniMaxProvider()
        case .deepseek:
            return DeepSeekProvider()
        case .custom:
            return CustomProvider()
        }
    }
    
    // MARK: - Shared configuration

    private func configuredService(usage: APIUsage) -> ResolvedAIService {
        AIConfigurationStore.resolve(image: usage == .image)
    }

    /// Learning uses the same endpoint, model and capability configuration as text processing.
    func processAnalysis(_ prompt: String) async throws -> String {
        let service = configuredService(usage: .text)
        let config = service.requestConfig(temperature: 0.3, maxTokens: 4096,
            deepThinking: UserDefaults.standard.bool(forKey: AppDefaults.Keys.enableDeepThinking))
        return try await executeWithRetry {
            try await self.getProviderInstance(for: service.provider).send(
                messages: [AIMessage(role: .user, text: prompt)], config: config)
        }
    }

    // MARK: - Text Processing
    
    func processText(_ text: String, mode: PromptMode = .defaultTranslation, sourceLanguage: String = "Auto Detect", targetLanguage: String = "简体中文", userPerception: String? = nil, userInstruction: String? = nil) async throws -> String {
        let service = configuredService(usage: .text)
        let preprocessedText = preprocessInput(text)
        let deepThinking = UserDefaults.standard.bool(forKey: AppDefaults.Keys.enableDeepThinking)
        let enhanceReview = service.shouldEnhanceReview(mode: mode, deepThinking: deepThinking)

        // 生成任务 Prompt，与 API 推理控制分离
        let prompts = generatePrompts(
            for: mode,
            text: preprocessedText,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            userPerception: userPerception,
            userInstruction: userInstruction,
            enhanceReview: enhanceReview
        )
        
        // 组装消息
        let messages: [AIMessage] = [
            AIMessage(role: .system, text: prompts.system),
            AIMessage(role: .user, text: prompts.user)
        ]
        
        let config = service.requestConfig(temperature: getTemperature(for: preprocessedText),
                                          maxTokens: getMaxTokens(for: preprocessedText), deepThinking: deepThinking)
        let rawResult = try await executeWithRetry {
            try await self.getProviderInstance(for: service.provider).send(messages: messages, config: config)
        }

        // 解析 JSON 响应
        let cleanJSON = extractJSON(from: rawResult)
        
        let result = try parseTranslationResult(from: cleanJSON, mode: mode)
        
        // Save to History
        HistoryManager.shared.addHistory(
            sourceText: text, // Save original text, not preprocessed
            targetText: result,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            mode: mode,
            customPerception: userPerception,
            customInstruction: userInstruction
        )
        
        return result
    }
    
    // MARK: - Image Recognition
    
    /// 处理图片识别（支持多 API 提供商）
    /// - Parameters:
    ///   - image: 要识别的图片
    ///   - mode: 提示词模式（翻译/预设/自定义）
    /// - Returns: AI 的响应文本
    func processImage(_ image: NSImage, mode: PromptMode = .defaultTranslation,
                      sourceLanguage: String = "Auto Detect", targetLanguage: String = "简体中文",
                      userPerception: String? = nil, userInstruction: String? = nil) async throws -> String {
        // Resolve once so the prompt and transport use the same capability snapshot.
        let service = configuredService(usage: .image)
        guard let imageData = imageToData(image) else {
            throw AIServiceError.configuration("Failed to encode image.")
        }
        let deepThinking = UserDefaults.standard.bool(forKey: AppDefaults.Keys.enableDeepThinking)
        let instruction = PromptCoordinator.shared.generateImageSystemPrompt(
            mode: mode, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage,
            enhanceReview: service.shouldEnhanceReview(mode: mode, deepThinking: deepThinking),
            customPerception: userPerception, customInstruction: userInstruction)
        let messages = [AIMessage(role: .system, text: instruction),
                        AIMessage(role: .user, text: "Please process this image according to the instructions.", image: imageData)]
        let config = service.requestConfig(temperature: 0.1, maxTokens: 4096, deepThinking: deepThinking)
        let rawResult = try await executeWithRetry {
            try await self.getProviderInstance(for: service.provider).send(messages: messages, config: config)
        }

        let parsedResult = parseImageResult(rawResult)
        
        // 保存到历史记录
        let capturedImage = image
        DispatchQueue.main.async {
            HistoryManager.shared.addHistory(
                sourceText: "",
                targetText: parsedResult,
                sourceLanguage: "Auto",
                targetLanguage: "Auto",
                mode: mode,
                image: capturedImage
            )
        }
        
        return parsedResult
    }
    
    // MARK: - Image Helpers
    
    /// Parse image recognition result from AI response
    private func parseImageResult(_ rawText: String) -> String {
        // 先清理可能的特殊 token
        let cleanedText = stripSpecialTokens(rawText)
        let cleanJSON = extractJSON(from: cleanedText)
        
        if let jsonData = cleanJSON.data(using: .utf8),
           let jsonObj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
            // 尝试从 JSON 中提取翻译结果
            if let translationResult = jsonObj["translation_result"] as? String {
                return translationResult
            } else if let result = jsonObj["result"] as? String {
                return result
            } else if let answer = jsonObj["answer"] as? String {
                return answer
            }
        }
        
        // 如果不是有效的 JSON，返回清理后的文本
        return cleanedText
    }
    
    /// 清理模型输出中的特殊 token
    private func stripSpecialTokens(_ text: String) -> String {
        var result = text
        
        // 常见的特殊 token 模式
        let patterns = [
            #"<\|begin_of_box\|>"#,
            #"<\|end_of_box\|>"#,
            #"<\|im_start\|>"#,
            #"<\|im_end\|>"#,
            #"<\|endoftext\|>"#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
            }
        }
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// 将 NSImage 转换为 Data
    private func imageToData(_ image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            return nil
        }
        return pngData
    }
    
    // MARK: - API Usage Context
    
    enum APIUsage {
        case text
        case image
    }
    
    // MARK: - Smart Pre-processing
    
    private func preprocessInput(_ text: String) -> String {
        // Heuristic: If short lines + frequent newlines -> Preserve newlines (Poetry/Code)
        // Heuristic: If long sentences broken by newlines mid-sentence -> Merge lines (PDF Copy)
        
        // Heuristic: Check if lines should be merged based on punctuation and next line capitalization
        let lines = text.components(separatedBy: .newlines)
        var mergedText = ""
        for i in 0..<lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            
            mergedText += line
            
            // If it's the last line, just end
            if i == lines.count - 1 {
                break
            }
            
            let nextLine = lines[i+1].trimmingCharacters(in: .whitespaces)
            if nextLine.isEmpty {
                mergedText += "\n"
                continue
            }
            
            // Check terminators
            let terminators = [".", "!", "?", "。", "！", "？"]
            if let lastChar = line.last, terminators.contains(String(lastChar)) {
                mergedText += "\n"
                continue
            }
            
            // Check if next line starts with lowercase (strong signal for continuation)
            if let firstChar = nextLine.first, firstChar.isLowercase {
                mergedText += " "
                continue
            }
            
            // Fallback: Length heuristic
            // If line is long (> 50 chars) and doesn't end in punctuation, assume prose -> merge
            // If line is short (< 50 chars), assume poetry/list -> keep newline
            if line.count > 50 {
                mergedText += " "
            } else {
                mergedText += "\n"
            }
        }
        
        return mergedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func containsMarkdown(_ text: String) -> Bool {
        let markdownMarkers = ["`", "**", "#", "[", "]"]
        for marker in markdownMarkers {
            if text.contains(marker) {
                return true
            }
        }
        return false
    }
    
    private func extractJSON(from text: String) -> String {
        var processingText = text
        
        // 1. First try to find Markdown code block using Regex
        // Matches ```json, ```JSON, or just ``` followed by content and ending with ```
        // Use GREEDY matching ([\s\S]*) to capture everything until the LAST closing fence.
        // This is necessary because the JSON content itself might contain code blocks (e.g. ```swift),
        // and lazy matching would stop prematurely at the internal backticks.
        let pattern = #"```(?:[a-zA-Z]+)?\s*([\s\S]*)\s*```"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: []),
           let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            processingText = String(text[range])
        }
        
        var jsonString = processingText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 2. Remove common AI preambles if we didn't match a code block (or if code block kept them inside?? unlikely but safe)
        // Only do this if we haven't already isolated a code block, OR do it anyway as cleanup.
        // Since we might have switched processingText, let's just clean up preambles from whatever we have.
        let preambles = [
            "Here is the translation:",
            "Translation:",
            "Result:",
            "Here is the result:",
            "Output:",
            "Response:"
        ]
        for preamble in preambles {
            if jsonString.hasPrefix(preamble) {
                jsonString = String(jsonString.dropFirst(preamble.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // Trim again after removing code fences (if any were removed by regex or preambles)
        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if it's already valid JSON by attempting to parse
        if jsonString.hasPrefix("{") {
            if let data = jsonString.data(using: .utf8),
               let _ = try? JSONSerialization.jsonObject(with: data) {
                // Already valid JSON, return as-is
                return jsonString
            }
        }
        
        // 3. Find the first '{' and use brace matching to find the corresponding '}'
        guard let startIndex = jsonString.firstIndex(of: "{") else {
            return jsonString
        }
        
        // Brace matching that respects string literals
        var braceCount = 0
        var inString = false
        var escapeNext = false
        var endIndex: String.Index?
        
        for (offset, char) in jsonString[startIndex...].enumerated() {
            let currentIndex = jsonString.index(startIndex, offsetBy: offset)
            
            if escapeNext {
                escapeNext = false
                continue
            }
            
            if char == "\\" { // This handles escaping any character, not just quotes
                escapeNext = true
                continue
            }
            
            if char == "\"" {
                inString = !inString
                continue
            }
            
            if !inString {
                if char == "{" {
                    braceCount += 1
                } else if char == "}" {
                    braceCount -= 1
                    if braceCount == 0 {
                        endIndex = currentIndex
                        break
                    }
                }
            }
        }
        
        if let endIndex = endIndex {
            return String(jsonString[startIndex...endIndex])
        }
        
        // Fallback: return from first brace to end
        return String(jsonString[startIndex...])
    }
    
    private func parseTranslationResult(from jsonString: String, mode: PromptMode) throws -> String {
        guard let data = jsonString.data(using: .utf8) else {
            throw NSError(domain: "TranslationError", code: 3, 
                         userInfo: [NSLocalizedDescriptionKey: "Failed to parse JSON"])
        }
        
        // 1. 首先嘗試標準 JSON 解析
        if let jsonObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let possibleKeys = [
                "translation_result",  // TranslationBuilder
                "result",              // CustomBuilder, PresetBuilder
                "answer",              // Fallback
                "content",             // Some AI variants
                "output",              // Alternative
                "text"                 // Plain response
            ]
            
            for key in possibleKeys {
                if let result = jsonObj[key] {
                    if let stringResult = result as? String, !stringResult.isEmpty {
                        return stringResult
                    } else if let dictResult = result as? [String: Any] {
                        return formatNestedResult(dictResult)
                    }
                }
            }
            
            // JSON 有效但沒有找到預期的 key
            let availableKeys = jsonObj.keys.joined(separator: ", ")
            print("DEBUG: Available JSON keys: \(availableKeys)")
            throw NSError(domain: "TranslationError", code: 3, 
                         userInfo: [NSLocalizedDescriptionKey: "No valid result key found. Available keys: \(availableKeys)"])
        }
        
        // 2. JSON 解析失敗：嘗試正則表達式直接提取
        // 這處理了當內層 JSON 中的引號未正確轉義的情況（智谱的markdown代码块问题）
        if let extracted = extractTranslationResultViaRegex(from: jsonString) {
            print("DEBUG: Used regex fallback to extract translation_result")
            return extracted
        }
        
        // 3. 如果不是 JSON 格式的純文本，直接返回
        let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && !trimmed.hasPrefix("{") {
            return trimmed
        }
        
        throw NSError(domain: "TranslationError", code: 3, 
                     userInfo: [NSLocalizedDescriptionKey: "Invalid JSON format: \(jsonString.prefix(100))"])
    }
    
    /// 使用正則表達式從 JSON-like 字符串中提取 translation_result 的值
    /// 當 JSON 包含未轉義的引號時（如智谱返回的 markdown code block），標準 JSON 解析會失敗
    /// 這個方法直接查找 key 並提取到 JSON 結束位置
    private func extractTranslationResultViaRegex(from text: String) -> String? {
        // 查找各種可能的 key
        let keys = ["translation_result", "result", "answer"]
        
        for key in keys {
            // 查找 "key": " 模式
            let pattern = "\"\(key)\"\\s*:\\s*\""
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
                  let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) else {
                continue
            }
            
            // 找到匹配後，從匹配結束位置開始提取值
            let valueStartIndex = text.index(text.startIndex, offsetBy: match.range.upperBound)
            
            // 策略：找到 JSON 結束模式 - 通常是 "\n} 或 "}
            // 由於內部引號已被解除轉義，我們不能依賴引號匹配
            // 而是查找 JSON 對象的結束標誌
            if let extractedValue = extractValueUntilJsonEnd(from: text, startingAt: valueStartIndex) {
                return extractedValue
            }
        }
        
        return nil
    }
    
    /// 提取值直到 JSON 結束
    /// 查找結束模式："} 或 "\n} 或 " }（引號後跟可選空白和右括號）
    private func extractValueUntilJsonEnd(from text: String, startingAt startIndex: String.Index) -> String? {
        let substring = String(text[startIndex...])
        
        // 查找結束模式：引號後跟可選空白/換行和右括號
        // 先嘗試精確匹配 "\n} 模式
        let endPatterns = [
            "\"\n}",      // 標準 JSON 格式
            "\"\r\n}",    // Windows 換行
            "\"}",        // 緊湊格式
            "\" }",       // 有空格
            "\"  }",      // 多空格
        ]
        
        var earliestEnd: String.Index?
        
        for pattern in endPatterns {
            if let range = substring.range(of: pattern) {
                let endPos = substring.index(range.lowerBound, offsetBy: 0)
                if earliestEnd == nil || endPos < earliestEnd! {
                    earliestEnd = endPos
                }
            }
        }
        
        // 如果找到了結束位置，提取內容
        if let endIndex = earliestEnd {
            var result = String(substring[..<endIndex])
            // 處理常見的轉義序列
            result = result.replacingOccurrences(of: "\\n", with: "\n")
            result = result.replacingOccurrences(of: "\\t", with: "\t")
            result = result.replacingOccurrences(of: "\\r", with: "\r")
            result = result.replacingOccurrences(of: "\\\"", with: "\"")
            result = result.replacingOccurrences(of: "\\\\", with: "\\")
            return result
        }
        
        // 備用方案：如果沒找到標準結束模式，返回到字符串結尾
        // 但排除最後的 } 和可能的 ] 字符
        var result = substring
        // 從末尾移除常見的 JSON 結束字符
        while result.hasSuffix("}") || result.hasSuffix("]") || result.hasSuffix("\n") || result.hasSuffix("\"") {
            result = String(result.dropLast())
        }
        
        if !result.isEmpty {
            // 處理轉義
            result = result.replacingOccurrences(of: "\\n", with: "\n")
            result = result.replacingOccurrences(of: "\\t", with: "\t")
            result = result.replacingOccurrences(of: "\\\"", with: "\"")
            result = result.replacingOccurrences(of: "\\\\", with: "\\")
            return result
        }
        
        return nil
    }
    
    // Format nested JSON object into readable string
    private func formatNestedResult(_ dict: [String: Any]) -> String {
        let priorityKeys = ["author", "title", "name", "answer"]
        
        // Get priority key-value pairs
        let priorityLines = priorityKeys.compactMap { key -> String? in
            guard let value = dict[key] else { return nil }
            return "\(key): \(value)"
        }
        
        // Get remaining key-value pairs
        let remainingLines = dict.keys
            .filter { !priorityKeys.contains($0) }
            .sorted()
            .compactMap { key in "\(key): \(dict[key]!)" }
        
        let allLines = priorityLines + remainingLines
        return allLines.isEmpty ? String(describing: dict) : allLines.joined(separator: "\n")
    }
    
    // MARK: - Prompt Generation Helper
    
    /// Generate system and user prompts based on mode (共享方法，消除重复)
    private func generatePrompts(
        for mode: PromptMode,
        text: String,
        sourceLanguage: String,
        targetLanguage: String,
        userPerception: String?,
        userInstruction: String?,
        enhanceReview: Bool = false  // 是否加强默认翻译的语义和格式检查
    ) -> (system: String, user: String) {
        // AI 自动检测语言，无需预先检测
        let systemPrompt: String
        if mode == .temporaryCustom {
            systemPrompt = PromptCoordinator.shared.generateCustomPrompt(
                inputContext: userPerception,
                outputRequirement: userInstruction
            )
        } else {
            systemPrompt = PromptCoordinator.shared.generateSystemPrompt(
                for: mode,
                withLearnedRules: true,
                enhanceReview: enhanceReview  // 加强翻译检查
            )
        }
        
        let userPrompt = PromptCoordinator.shared.generateUserPrompt(
            text: text,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            mode: mode
        )
        
        return (systemPrompt, userPrompt)
    }
    
    // MARK: - API Optimization Helpers
    
    private func getTemperature(for text: String) -> Double {
        // Technical/Short text: precise
        if containsMarkdown(text) || text.count < 50 {
            return 0.1
        }
        
        // Legal text: zero tolerance
        if text.contains("Force Majeure") || text.contains("pursuant to") || 
           text.contains("不可抗力") || text.contains("根据") {
            return 0.0
        }
        
        // Literary long text: creative
        if (text.contains("。") || text.contains(".")) && text.count > 200 {
            return 0.7
        }
        
        // Default
        return 0.3
    }
    
    private func getMaxTokens(for text: String) -> Int {
        // Translation output is typically 1.5-3x input length (especially CN<->EN)
        // Plus JSON overhead (detected_type, etc.) ~500 tokens
        // No hard cap - let the provider's native limit handle it
        let estimatedTokens = text.count * 3 + 500  // 3x for translation expansion + JSON overhead
        return max(1024, estimatedTokens)  // Minimum 1024 tokens
    }
    
    private func validateResponse(_ response: TranslationResponse, originalText: String) throws {
        // Check if empty
        guard !response.translation_result.isEmpty else {
            throw NSError(domain: "TranslationError", code: 2, 
                         userInfo: [NSLocalizedDescriptionKey: "Empty translation result"])
        }
        
        // Check if it's still JSON (Schema self-translation bug)
        let trimmed = response.translation_result.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") && trimmed.hasSuffix("}") && trimmed.contains("detected_type") {
            throw NSError(domain: "TranslationError", code: 3, 
                         userInfo: [NSLocalizedDescriptionKey: "Invalid translation: AI returned schema instead of text"])
        }
        
        // Check if abnormally long (shouldn't be 10x original)
        if response.translation_result.count > originalText.count * 10 {
            throw NSError(domain: "TranslationError", code: 4, 
                         userInfo: [NSLocalizedDescriptionKey: "Translation abnormally long"])
        }
    }
    
    private func executeWithRetry<T>(
        maxRetries: Int = 3,
        operation: () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        
        for attempt in 0..<maxRetries {
            do {
                return try await operation()
            } catch {
                lastError = error
                if error is CancellationError { throw error }
                if let serviceError = error as? AIServiceError, !serviceError.shouldRetry { throw error }
                if let urlError = error as? URLError, urlError.code == .cancelled { throw error }

                // Exponential backoff: 1s, 2s, 4s
                if attempt < maxRetries - 1 {
                    let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                    try await Task.sleep(nanoseconds: delay)
                }
            }
        }
        
        throw lastError ?? NSError(domain: "TranslationError", code: 99, 
                                   userInfo: [NSLocalizedDescriptionKey: "Unknown error after retries"])
    }
}
