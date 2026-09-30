import Foundation

final class GeminiProvider: AIProvider {
    let provider: APIProvider = .gemini

    func send(messages: [AIMessage], config: AIRequestConfig) async throws -> String {
        try await AIHTTPTransport().send(messages: messages, config: config)
    }
}
