import Foundation

final class MiniMaxProvider: AIProvider {
    let provider: APIProvider = .minimax

    func send(messages: [AIMessage], config: AIRequestConfig) async throws -> String {
        try await AIHTTPTransport().send(messages: messages, config: config)
    }
}
