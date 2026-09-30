import Foundation

final class DeepSeekProvider: AIProvider {
    let provider: APIProvider = .deepseek

    func send(messages: [AIMessage], config: AIRequestConfig) async throws -> String {
        try await AIHTTPTransport().send(messages: messages, config: config)
    }
}
