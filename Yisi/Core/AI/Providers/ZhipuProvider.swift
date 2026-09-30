import Foundation

final class ZhipuProvider: AIProvider {
    let provider: APIProvider = .zhipu

    func send(messages: [AIMessage], config: AIRequestConfig) async throws -> String {
        try await AIHTTPTransport().send(messages: messages, config: config)
    }
}
