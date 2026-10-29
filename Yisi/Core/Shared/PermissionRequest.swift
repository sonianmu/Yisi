import Foundation

enum PermissionRequest {
    enum Outcome: Equatable {
        case granted
        case awaitingUser
        case registrationFailed
    }

    static func perform(preflight: () -> Bool, registerApplication: () -> Bool,
                        requestAccess: () -> Bool) -> Outcome {
        if preflight() { return .granted }
        guard registerApplication() else { return .registrationFailed }
        if requestAccess() || preflight() { return .granted }
        return .awaitingUser
    }
}
