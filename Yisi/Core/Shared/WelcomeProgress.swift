enum WelcomeProgress {
    static func initialStep(savedStep: Int, accessibilityGranted: Bool, screenCaptureGranted: Bool) -> Int {
        if accessibilityGranted && screenCaptureGranted { return 4 }
        if savedStep >= 2 {
            return accessibilityGranted ? 3 : 2
        }
        if accessibilityGranted { return 3 }
        return min(max(savedStep, 0), 1)
    }

    static func shouldOpenHome(savedStep: Int, accessibilityGranted: Bool, screenCaptureGranted: Bool) -> Bool {
        savedStep >= 2 && accessibilityGranted && screenCaptureGranted
    }

    enum PermissionAction: Equatable {
        case none, screenRecording, ready, home, restart
    }

    static func permissionAction(step: Int, accessibility: Bool, screenCapture: Bool,
                                 previouslyScreenCapture: Bool, recovering: Bool) -> PermissionAction {
        guard step == 2 || step == 3 else { return .none }
        if step == 3 && !previouslyScreenCapture && screenCapture { return .restart }
        guard accessibility else { return .none }
        if screenCapture { return recovering ? .home : .ready }
        return step == 2 ? .screenRecording : .none
    }

}
