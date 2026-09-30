import Foundation

final class CustomProvider: AIProvider {
    let provider: APIProvider = .custom

    func send(messages: [AIMessage], config: AIRequestConfig) async throws -> String {
        try await AIHTTPTransport().send(messages: messages, config: config)
    }
}
