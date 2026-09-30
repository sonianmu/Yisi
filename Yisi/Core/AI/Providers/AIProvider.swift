import Foundation
import AppKit

// MARK: - 统一的请求配置要素

struct AIRequestConfig {
    let apiKey: String
    let model: String
    let temperature: Double
    let maxTokens: Int
    let enableNativeReasoning: Bool // 产品的深度思考偏好，由能力配置映射到 API 参数
    let apiProtocol: AIProtocol
    let baseURL: String
    let capabilities: ModelCapabilities
}

// MARK: - 统一的消息结构 (兼容文本和多模态)

enum AIMessageRole: String {
    case system
    case user
    case assistant
}

struct AIMessageContent {
    let text: String
    let image: Data?
    
    init(text: String, image: Data? = nil) {
        self.text = text
        self.image = image
    }
}

struct AIMessage {
    let role: AIMessageRole
    let content: AIMessageContent
    
    init(role: AIMessageRole, content: AIMessageContent) {
        self.role = role
        self.content = content
    }
    
    init(role: AIMessageRole, text: String, image: Data? = nil) {
        self.role = role
        self.content = AIMessageContent(text: text, image: image)
    }
}

// MARK: - 统一接口协议

protocol AIProvider {
    var provider: APIProvider { get }
    func send(messages: [AIMessage], config: AIRequestConfig) async throws -> String
}
