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
        savedStep >= 3 && accessibilityGranted && screenCaptureGranted
    }
}
