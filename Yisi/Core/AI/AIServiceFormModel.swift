import Foundation
import Combine

/// Shared by the welcome page and its form so navigation can wait for a saved configuration.
@MainActor final class AIServiceFormModel: ObservableObject {
    @Published var draft: AIServiceDraft
    @Published private(set) var testing = false
    @Published private(set) var status = ""
    @Published private(set) var succeeded = false
    private var savedDraft: AIServiceDraft?
    private let save: (AIServiceDraft) async throws -> String

    init(draft: AIServiceDraft, save: @escaping (AIServiceDraft) async throws -> String = {
        try await $0.testAndSave()
    }) {
        self.draft = draft
        self.save = save
    }

    func clearStatus() { status = "" }

    /// A successful result is the only condition under which onboarding may advance.
    func testAndSave(reuseSaved: Bool = false) async -> Bool {
        guard !testing else { return false }
        if reuseSaved, savedDraft == draft { return true }
        let submitted = draft
        testing = true
        status = ""
        defer { testing = false }
        do {
            let response = try await save(submitted)
            savedDraft = submitted
            succeeded = true
            status = "Connection successful. Settings saved.".localized + "\n" + String(response.prefix(160))
            // Never advance with edits that were not part of the successful request.
            return submitted == draft
        } catch {
            guard !Task.isCancelled else { return false }
            succeeded = false
            status = "Test failed. Previous settings were kept.".localized + "\n" + error.localizedDescription
            return false
        }
    }
}
