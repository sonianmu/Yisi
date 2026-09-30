import SwiftUI
import ScreenCaptureKit

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
            (colorScheme == .dark ? Color(hex: "202024") : Color(hex: "F8F7F4"))
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
        .onDisappear { timer?.invalidate() }
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
                .foregroundColor(.white).padding(14)
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
            Text("Enter your API key and model, then test and save. You can also configure this later in Settings.".localized)
                .font(.system(size: 12)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                AIServiceConfigurationForm().padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            HStack {
                Button("Set up later".localized) { withAnimation { currentStep = 2 } }
                    .buttonStyle(.plain).foregroundColor(.secondary)
                Spacer()
                Button("Next".localized) { withAnimation { currentStep = 2 } }
                    .buttonStyle(.plain).foregroundColor(AppColors.primary)
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
                } else {
                    let opts: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                    AXIsProcessTrustedWithOptions(opts)
                }
            }) {
                Text(accessibilityGranted ? "Next".localized : "Enable".localized)
                    .font(.system(size: 14, weight: .medium, design: .serif))
                    .foregroundColor(accessibilityGranted ? .white : AppColors.primary)
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

            Text("Enable Yisi in System Settings. If it is missing, reveal the app in Finder and add it with the + button.".localized)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 44)
                .padding(.top, 16)

            Button("Show App in Finder".localized) {
                NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .padding(.top, 10)

            RoundedRectangle(cornerRadius: 1)
                .fill(AppColors.primary.opacity(screenCaptureGranted ? 0.5 : 0.12))
                .frame(width: screenCaptureGranted ? 120 : 40, height: 2)
                .animation(.easeInOut(duration: 0.6), value: screenCaptureGranted)
                .padding(.top, 24)

            Spacer()

            Button(action: {
                if screenCaptureGranted {
                    withAnimation { currentStep = 4 }
                } else {
                    requestScreenCapturePermission()
                }
            }) {
                Text(requestingScreenCapture ? "Waiting for authorization…".localized : (screenCaptureGranted ? "Next".localized : "Enable".localized))
                    .font(.system(size: 14, weight: .medium, design: .serif))
                    .foregroundColor(screenCaptureGranted ? .white : AppColors.primary)
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
                    .font(.system(size: 14, weight: .medium)).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(AppColors.primary, in: RoundedRectangle(cornerRadius: 8))
            }
                .buttonStyle(.plain)
                .padding(.bottom, 36)
        }
        .padding(.horizontal, 40)
        .onAppear { UserDefaults.standard.set(true, forKey: AppDefaults.Keys.welcomeCompleted) }
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
        // Wait for ScreenCaptureKit's authorization request to finish before
        // opening Settings, so the app's permission entry has time to appear.
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { _, _ in
            DispatchQueue.main.async {
                requestingScreenCapture = false
                if CGPreflightScreenCaptureAccess() {
                    relaunchApp()
                } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            let newAcc = AXIsProcessTrusted()
            let newScr = CGPreflightScreenCaptureAccess()

            if currentStep == 3 && !screenCaptureGranted && newScr {
                relaunchApp()
                return
            }

            accessibilityGranted = newAcc
            screenCaptureGranted = newScr
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
