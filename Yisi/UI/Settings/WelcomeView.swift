import SwiftUI
import ScreenCaptureKit

struct WelcomeView: View {
    @State private var currentStep: Int
    @State private var accessibilityGranted: Bool
    @State private var screenCaptureGranted: Bool
    @State private var timer: Timer?
    @State private var pulsing = false
    @State private var heroLoaded = false
    @State private var readyLoaded = false
    @State private var requestingScreenCapture = false
    @State private var relaunching = false

    @AppStorage(AppDefaults.Keys.apiProvider) private var apiProvider: String = AppDefaults.apiProvider
    @AppStorage(AppDefaults.Keys.geminiApiKey) private var geminiKey: String = ""
    @AppStorage(AppDefaults.Keys.openaiApiKey) private var openaiKey: String = ""
    @AppStorage(AppDefaults.Keys.zhipuApiKey) private var zhipuKey: String = ""
    @AppStorage(AppDefaults.Keys.minimaxApiKey) private var minimaxKey: String = ""
    @AppStorage(AppDefaults.Keys.deepseekApiKey) private var deepseekKey: String = ""

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

    private var hasApiKey: Bool {
        switch apiProvider {
        case "Gemini": return !geminiKey.isEmpty
        case "OpenAI": return !openaiKey.isEmpty
        case "MiniMax": return !minimaxKey.isEmpty
        case "DeepSeek": return !deepseekKey.isEmpty
        default: return !zhipuKey.isEmpty
        }
    }

    var body: some View {
        ZStack {
            ThemeBackground().edgesIgnoringSafeArea(.all)
            ambientGlow
                .opacity(currentStep == 0 || currentStep == 4 ? 1 : 0.3)
                .animation(.easeInOut(duration: 0.6), value: currentStep)

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

    // MARK: - Ambient Glow

    private var ambientGlow: some View {
        ZStack {
            RadialGradient(
                gradient: Gradient(colors: [
                    AppColors.yisiPurple.opacity(0.1),
                    AppColors.yisiPurple.opacity(0)
                ]),
                center: UnitPoint(x: 0.5, y: 0.35),
                startRadius: 20,
                endRadius: 200
            )
            RadialGradient(
                gradient: Gradient(colors: [
                    AppColors.yisiLight.opacity(0.06),
                    AppColors.yisiLight.opacity(0)
                ]),
                center: UnitPoint(x: 0.3, y: 0.65),
                startRadius: 0,
                endRadius: 160
            )
        }
    }

    // MARK: - Page 0: Hero

    private var heroPage: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                WelcomeLoadingBars()
                    .frame(width: 200, height: 60)
                    .opacity(heroLoaded ? 0 : 1)

                VStack(spacing: 0) {
                    Text("Yisi")
                        .font(.system(size: 30, weight: .light, design: .serif))
                        .tracking(2)
                        .foregroundColor(.primary)

                    Text("有Yisi，才有意思。".localized)
                        .font(.system(size: 12, weight: .regular, design: .serif))
                        .foregroundColor(.secondary.opacity(0.7))
                        .padding(.top, 8)
                }
                .opacity(heroLoaded ? 1 : 0)
                .offset(y: heroLoaded ? 0 : 8)
            }
            .animation(.easeInOut(duration: 0.8), value: heroLoaded)

            Spacer()

            gradientLine
                .padding(.bottom, 32)
                .opacity(heroLoaded ? 1 : 0)
                .animation(.easeOut(duration: 0.6).delay(0.2), value: heroLoaded)

            filledButton("Next".localized) {
                withAnimation { currentStep = 1 }
            }
            .padding(.bottom, 36)
            .opacity(heroLoaded ? 1 : 0)
            .animation(.easeOut(duration: 0.5).delay(0.4), value: heroLoaded)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                heroLoaded = true
            }
        }
    }

    // MARK: - Page 1: AI Config

    private var aiConfigPage: some View {
        VStack(spacing: 0) {
            Text("AI Service".localized)
                .font(.system(size: 22, weight: .medium, design: .serif))
                .foregroundColor(.primary)
                .padding(.top, 48)

            Text("Optional. You can set this up later in Settings.".localized)
                .font(.system(size: 12, design: .serif))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            VStack(spacing: 14) {
                Picker("", selection: $apiProvider) {
                    Text("Gemini").tag("Gemini")
                    Text("OpenAI").tag("OpenAI")
                    Text("Zhipu AI").tag("Zhipu AI")
                    Text("MiniMax").tag("MiniMax")
                    Text("DeepSeek").tag("DeepSeek")
                }
                .pickerStyle(.menu)
                .frame(width: 280)

                Group {
                    if apiProvider == "Gemini" {
                        SecureField("Gemini API Key", text: $geminiKey)
                    } else if apiProvider == "OpenAI" {
                        SecureField("OpenAI API Key", text: $openaiKey)
                    } else if apiProvider == "MiniMax" {
                        SecureField("MiniMax API Key", text: $minimaxKey)
                    } else if apiProvider == "DeepSeek" {
                        SecureField("DeepSeek API Key", text: $deepseekKey)
                    } else {
                        SecureField("Zhipu API Key", text: $zhipuKey)
                    }
                }
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 13))
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(AppColors.primary.opacity(0.04))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppColors.primary.opacity(0.1), lineWidth: 0.5)
                )
                .frame(width: 280)
            }
            .padding(.top, 32)

            Spacer()

            nextButton(highlighted: hasApiKey) {
                withAnimation { currentStep = 2 }
            }

            Button(action: { withAnimation { currentStep = 2 } }) {
                Text("Skip".localized)
                    .font(.system(size: 12, design: .serif))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .animation(.easeInOut(duration: 0.3), value: hasApiKey)
    }

    // MARK: - Page 2: Accessibility

    private var accessibilityPage: some View {
        VStack(spacing: 0) {
            Spacer()

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
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                WelcomeLoadingBars()
                    .frame(width: 200, height: 60)
                    .opacity(readyLoaded ? 0 : 1)

                VStack(spacing: 0) {
                    Text("Yisi")
                        .font(.system(size: 30, weight: .light, design: .serif))
                        .tracking(2)
                        .foregroundColor(.primary)

                    Text("有Yisi，才有意思。".localized)
                        .font(.system(size: 12, weight: .regular, design: .serif))
                        .foregroundColor(.secondary.opacity(0.7))
                        .padding(.top, 8)
                }
                .opacity(readyLoaded ? 1 : 0)
                .offset(y: readyLoaded ? 0 : 8)
            }
            .animation(.easeInOut(duration: 0.8), value: readyLoaded)

            gradientLine
                .padding(.top, 16)
                .opacity(readyLoaded ? 1 : 0)
                .animation(.easeOut(duration: 0.6).delay(0.2), value: readyLoaded)

            Spacer()

            filledButton("Get Started".localized) {
                onComplete()
            }
            .padding(.bottom, 36)
            .opacity(readyLoaded ? 1 : 0)
            .animation(.easeOut(duration: 0.5).delay(0.4), value: readyLoaded)
        }
        .onAppear {
            UserDefaults.standard.set(true, forKey: AppDefaults.Keys.welcomeCompleted)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                readyLoaded = true
            }
        }
    }

    // MARK: - Shared Components

    private func filledButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium, design: .serif))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppColors.primary)
                )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 52)
    }

    private func nextButton(highlighted: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Next".localized)
                .font(.system(size: 14, weight: .medium, design: .serif))
                .foregroundColor(highlighted ? .white : AppColors.primary.opacity(0.5))
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(highlighted ? AppColors.primary : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            highlighted ? Color.clear : AppColors.primary.opacity(0.15),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 52)
    }

    private var gradientLine: some View {
        RoundedRectangle(cornerRadius: 0.5)
            .fill(
                LinearGradient(
                    colors: [
                        AppColors.primary.opacity(0),
                        AppColors.primary.opacity(0.2),
                        AppColors.primary.opacity(0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: 160, height: 1)
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

// MARK: - Welcome Loading Bars

private struct WelcomeLoadingBars: View {
    @State private var isAnimating = false

    private let ratios: [CGFloat] = [0.85, 0.55, 0.35]
    private let barHeight: CGFloat = 5
    private let spacing: CGFloat = 7

    var body: some View {
        GeometryReader { geo in
            let baseWidth = geo.size.width * 0.85
            VStack(spacing: spacing) {
                ForEach(0..<3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(isAnimating ? AppColors.yisiLight : AppColors.mist)
                        .frame(width: baseWidth * ratios[i], height: barHeight)
                        .scaleEffect(x: isAnimating ? 1.0 : 0.85, y: 1.0)
                        .opacity(isAnimating ? 1.0 : 0.4)
                        .animation(
                            .easeInOut(duration: 0.9)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.15),
                            value: isAnimating
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .onAppear { isAnimating = true }
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
