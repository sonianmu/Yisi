import SwiftUI
import CoreGraphics

struct WelcomeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppDefaults.Keys.appTheme) private var appTheme = AppDefaults.appTheme
    @State private var currentStep: Int
    @State private var accessibilityGranted: Bool
    @State private var screenCaptureGranted: Bool
    @State private var timer: Timer?
    @State private var pulsing = false
    @State private var requestingScreenCapture = false
    @State private var relaunching = false
    @State private var requestedAccessibility = false
    @State private var requestedScreenCapture = false
    @State private var finishingWelcome = false
    @StateObject private var aiServiceForm = AIServiceFormModel(draft: AIServiceDraft.load(image: false))
    @State private var saveTask: Task<Void, Never>?

    var onComplete: () -> Void
    private let tracksProgress: Bool

    init(forceStartFromHero: Bool = false, onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        self.tracksProgress = !forceStartFromHero
        let acc = AXIsProcessTrusted()
        let scr = CGPreflightScreenCaptureAccess()
        _accessibilityGranted = State(initialValue: acc)
        _screenCaptureGranted = State(initialValue: scr)
        if forceStartFromHero {
            _currentStep = State(initialValue: 0)
        } else {
            _currentStep = State(initialValue: WelcomeProgress.initialStep(
                savedStep: UserDefaults.standard.integer(forKey: AppDefaults.Keys.welcomeStep),
                accessibilityGranted: acc, screenCaptureGranted: scr
            ))
        }
    }

    var body: some View {
        ZStack {
            ThemeBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if currentStep >= 1 && currentStep <= 3 {
                    WelcomeStepIndicator(current: currentStep - 1, total: 3)
                        .padding(.top, 24)
                        .transition(.opacity)
                }

                ZStack {
                    if currentStep == 0 { heroPage.transition(pageTransition) }
                    if currentStep == 1 { aiConfigPage.transition(pageTransition) }
                    if currentStep == 2 { accessibilityPage.transition(pageTransition) }
                    if currentStep == 3 { screenRecordingPage.transition(pageTransition) }
                    if currentStep == 4 { readyPage.transition(.opacity) }
                }
                .animation(.easeInOut(duration: 0.4), value: currentStep)
            }
        }
        .frame(width: 420, height: 520)
        .preferredColorScheme(ColorScheme(from: appTheme))
        .onAppear {
            startPolling()
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
        .onDisappear {
            timer?.invalidate()
            saveTask?.cancel()
        }
        .onChange(of: currentStep) { _, step in
            if tracksProgress {
                UserDefaults.standard.set(step, forKey: AppDefaults.Keys.welcomeStep)
            }
        }
    }

    private var pageTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    // MARK: - Welcome

    private var brandMark: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach([64.0, 42.0, 24.0], id: \.self) { width in
                Capsule().fill(AppColors.primary).frame(width: width, height: 6)
            }
        }
        .accessibilityHidden(true)
    }

    private var heroPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandMark.padding(.top, 56)
            Text("Yisi")
                .font(.system(size: 48, weight: .light, design: .serif))
                .tracking(1).padding(.top, 26)
            Text("有Yisi，才有意思。".localized)
                .font(.system(size: 15, design: .serif))
                .foregroundColor(.secondary).padding(.top, 8)
            Rectangle().fill(AppColors.primary.opacity(0.15)).frame(height: 1).padding(.vertical, 28)
            Text("Select. Translate. Keep your flow.".localized)
                .font(.system(size: 19, weight: .medium, design: .serif))
            Text("Translate selected text or screenshots, without leaving what you are doing.".localized)
                .font(.system(size: 13)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 10)
            Spacer()
            Button { withAnimation { currentStep = 1 } } label: {
                HStack {
                    Text("Next".localized)
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AppColors.onAccent).padding(14)
                .background(AppColors.primary, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain).padding(.bottom, 36)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - AI Configuration

    private var aiConfigPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AI Service".localized)
                .font(.system(size: 24, weight: .medium, design: .serif))
                .padding(.top, 26)
            Text("Enter your API key and model. Next will test and save before continuing. You can also configure this later in Settings.".localized)
                .font(.system(size: 12)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                AIServiceConfigurationForm(form: aiServiceForm).padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            HStack {
                Button("Set up later".localized) { withAnimation { currentStep = 2 } }
                    .buttonStyle(.plain).foregroundColor(.secondary)
                    .disabled(aiServiceForm.testing)
                Spacer()
                Button("Next".localized) {
                    saveTask = Task { @MainActor in
                        guard await aiServiceForm.testAndSave(reuseSaved: true), !Task.isCancelled else { return }
                        withAnimation { currentStep = 2 }
                    }
                }
                    .buttonStyle(.plain).foregroundColor(AppColors.primary)
                    .disabled(aiServiceForm.testing)
            }
            .font(.system(size: 13)).padding(.bottom, 30)
        }
        .padding(.horizontal, 36)
    }

    // MARK: - Page 2: Accessibility

    private var accessibilityPage: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "command")
                .font(.system(size: 30, weight: .light))
                .foregroundColor(AppColors.primary)
                .frame(width: 72, height: 72)
                .background(AppColors.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
                .padding(.bottom, 24)

            Text("Accessibility".localized)
                .font(.system(size: 22, weight: .medium, design: .serif))
                .foregroundColor(.primary)

            Text("Global hotkeys & text capture".localized)
                .font(.system(size: 12, design: .serif))
                .foregroundColor(.secondary)
                .padding(.top, 8)

            RoundedRectangle(cornerRadius: 1)
                .fill(AppColors.primary.opacity(accessibilityGranted ? 0.5 : 0.12))
                .frame(width: accessibilityGranted ? 120 : 40, height: 2)
                .animation(.easeInOut(duration: 0.6), value: accessibilityGranted)
                .padding(.top, 24)

            Spacer()

            Button(action: {
                if accessibilityGranted {
                    withAnimation { currentStep = 3 }
                } else if requestedAccessibility {
                    openPermissionSettings("Privacy_Accessibility")
                } else {
                    requestAccessibilityPermission()
                }
            }) {
                Text((accessibilityGranted ? "Next" : (requestedAccessibility ? "Open System Settings" : "Enable")).localized)
                    .font(.system(size: 14, weight: .medium, design: .serif))
                    .foregroundColor(accessibilityGranted ? AppColors.onAccent : AppColors.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(accessibilityGranted ? AppColors.primary : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                accessibilityGranted
                                    ? Color.clear
                                    : AppColors.primary.opacity(pulsing ? 0.45 : 0.15),
                                lineWidth: 1
                            )
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 52)
            .padding(.bottom, 36)
            .animation(.easeInOut(duration: 0.4), value: accessibilityGranted)
        }
    }

    // MARK: - Page 3: Screen Recording

    private var screenRecordingPage: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "viewfinder")
                .font(.system(size: 30, weight: .light))
                .foregroundColor(AppColors.primary)
                .frame(width: 72, height: 72)
                .background(AppColors.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
                .padding(.bottom, 24)

            Text("Screen Recording".localized)
                .font(.system(size: 22, weight: .medium, design: .serif))
                .foregroundColor(.primary)

            Text("Screenshot translation".localized)
                .font(.system(size: 12, design: .serif))
                .foregroundColor(.secondary)
                .padding(.top, 8)

            Text("Turn on Yisi in System Settings, then return here.".localized)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 44)
                .padding(.top, 16)

            RoundedRectangle(cornerRadius: 1)
                .fill(AppColors.primary.opacity(screenCaptureGranted ? 0.5 : 0.12))
                .frame(width: screenCaptureGranted ? 120 : 40, height: 2)
                .animation(.easeInOut(duration: 0.6), value: screenCaptureGranted)
                .padding(.top, 24)

            Spacer()

            Button(action: {
                if screenCaptureGranted {
                    withAnimation { currentStep = 4 }
                } else if requestedScreenCapture {
                    openPermissionSettings("Privacy_ScreenCapture")
                } else {
                    requestScreenCapturePermission()
                }
            }) {
                Text((requestingScreenCapture ? "Waiting for authorization…" : (screenCaptureGranted ? "Next" : (requestedScreenCapture ? "Open System Settings" : "Enable"))).localized)
                    .font(.system(size: 14, weight: .medium, design: .serif))
                    .foregroundColor(screenCaptureGranted ? AppColors.onAccent : AppColors.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(screenCaptureGranted ? AppColors.primary : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                screenCaptureGranted
                                    ? Color.clear
                                    : AppColors.primary.opacity(pulsing ? 0.45 : 0.15),
                                lineWidth: 1
                            )
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(requestingScreenCapture)
            .padding(.horizontal, 52)
            .padding(.bottom, 36)
            .animation(.easeInOut(duration: 0.4), value: screenCaptureGranted)
        }
    }

    // MARK: - Page 4: Ready

    private var readyPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandMark.padding(.top, 64)
            Text("You are ready.".localized)
                .font(.system(size: 30, weight: .light, design: .serif)).padding(.top, 32)
            Text("Yisi is in your menu bar. Select text or take a screenshot to begin.".localized)
                .font(.system(size: 13)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 14)
            Spacer()
            Button(action: onComplete) {
                Text("Get Started".localized)
                    .font(.system(size: 14, weight: .medium)).foregroundColor(AppColors.onAccent)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(AppColors.primary, in: RoundedRectangle(cornerRadius: 8))
            }
                .buttonStyle(.plain)
                .padding(.bottom, 36)
        }
        .padding(.horizontal, 40)
        .onAppear {
            if tracksProgress {
                PermissionMigration.completeAuthorization(defaults: .standard)
                UserDefaults.standard.set(true, forKey: AppDefaults.Keys.welcomeCompleted)
            }
        }
    }

    // MARK: - Helpers

    private func requestScreenCapturePermission() {
        guard !requestingScreenCapture else { return }
        if tracksProgress {
            // System Settings may terminate us before the request callback runs.
            UserDefaults.standard.set(3, forKey: AppDefaults.Keys.welcomeStep)
            UserDefaults.standard.synchronize()
        }
        requestingScreenCapture = true
        DispatchQueue.main.async {
            defer { requestingScreenCapture = false }
            NSApp.activate(ignoringOtherApps: true)
            let outcome = PermissionRequest.perform(
                preflight: { CGPreflightScreenCaptureAccess() },
                registerApplication: registerCurrentApplication,
                requestAccess: {
                    requestedScreenCapture = true
                    return CGRequestScreenCaptureAccess()
                }
            )
            if outcome == .granted {
                relaunchApp()
            } else if outcome == .registrationFailed {
                showPermissionRegistrationFailure()
            }
        }
    }

    private func requestAccessibilityPermission() {
        if tracksProgress {
            UserDefaults.standard.set(2, forKey: AppDefaults.Keys.welcomeStep)
            UserDefaults.standard.synchronize()
        }
        let outcome = PermissionRequest.perform(
            preflight: { AXIsProcessTrusted() },
            registerApplication: registerCurrentApplication,
            requestAccess: {
                guard !requestedAccessibility else { return AXIsProcessTrusted() }
                requestedAccessibility = true
                let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                return AXIsProcessTrustedWithOptions(options)
            }
        )
        if outcome == .registrationFailed { showPermissionRegistrationFailure() }
        refreshAuthorization()
    }

    private func registerCurrentApplication() -> Bool {
        PermissionReset.registerApplication(bundleID: Bundle.main.bundleIdentifier ?? "", appPath: Bundle.main.bundlePath)
    }

    private func openPermissionSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func showPermissionRegistrationFailure() {
        let alert = AppAlert()
        alert.alertStyle = .warning
        alert.messageText = "Could not prepare authorization".localized
        alert.informativeText = "Please reopen the installed Yisi app and try again. Existing permissions have not been reset.".localized
        alert.runModal()
    }

    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            refreshAuthorization()
        }
    }

    private func refreshAuthorization() {
        guard !relaunching, !finishingWelcome else { return }
        let newAcc = AXIsProcessTrusted()
        let newScr = CGPreflightScreenCaptureAccess()
        if newAcc != accessibilityGranted || newScr != screenCaptureGranted {
            NSLog("Yisi authorization changed: path=%@ step=%ld accessibility=%d screenCapture=%d",
                  Bundle.main.bundlePath, currentStep, newAcc ? 1 : 0, newScr ? 1 : 0)
        }
        let action = WelcomeProgress.permissionAction(step: currentStep, accessibility: newAcc,
            screenCapture: newScr, previouslyScreenCapture: screenCaptureGranted,
            recovering: tracksProgress && UserDefaults.standard.bool(forKey: AppDefaults.Keys.welcomeCompleted))
        accessibilityGranted = newAcc
        screenCaptureGranted = newScr
        switch action {
        case .none: break
        case .screenRecording: withAnimation { currentStep = 3 }
        case .ready: withAnimation { currentStep = 4 }
        case .restart: relaunchApp()
        case .home:
            finishingWelcome = true
            timer?.invalidate()
            UserDefaults.standard.set(3, forKey: AppDefaults.Keys.welcomeStep)
            PermissionMigration.completeAuthorization(defaults: .standard)
            UserDefaults.standard.synchronize()
            onComplete()
        }
    }

    private func relaunchApp() {
        guard !relaunching else { return }
        relaunching = true
        if tracksProgress {
            UserDefaults.standard.set(3, forKey: AppDefaults.Keys.welcomeStep)
        }
        timer?.invalidate()
        UserDefaults.standard.synchronize()

        let path = Bundle.main.bundlePath
        guard path.hasSuffix(".app") else {
            withAnimation { currentStep = 4 }
            return
        }

        let task = Process()
        task.launchPath = "/bin/sh"
        var arguments = ["-c", "sleep 0.5; exec /usr/bin/open -n \"$@\"", "yisi-relaunch", path]
        if ProcessInfo.processInfo.arguments.contains("-auto_check_updates") {
            arguments += ["--args", "-auto_check_updates", "NO"]
        }
        task.arguments = arguments
        try? task.run()
        NSApp.terminate(nil)
    }
}

// MARK: - Step Indicator

private struct WelcomeStepIndicator: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i <= current
                        ? AppColors.primary.opacity(0.5)
                        : AppColors.primary.opacity(0.1))
                    .frame(width: i == current ? 24 : 8, height: 3)
                    .animation(.easeInOut(duration: 0.3), value: current)
            }
        }
    }
}
