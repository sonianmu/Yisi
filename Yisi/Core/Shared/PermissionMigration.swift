import Foundation
import Security

/// Only migration metadata is written here; credentials and user files are never accessed.
enum PermissionMigration {
    static let stateKey = "permission_migration_state_v1"
    static let pendingKey = "permission_migration_pending"

    struct Identity: Codable, Equatable {
        let version: String
        let requirement: String?
    }

    struct State: Codable {
        let identity: Identity
        let attemptedServices: [String]
        var failedServices: [String]
    }

    struct Plan {
        let identity: Identity
        let services: [String]
    }

    static func runningIdentity(bundle: Bundle = .main) -> Identity? {
        guard bundle.bundleIdentifier == "com.sonianmu.yisi", bundle.bundleURL.pathExtension == "app",
              let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String,
              version != "0.0.0", !bundle.bundlePath.contains("/Debug/") else { return nil }
        var code: SecCode?
        var staticCode: SecStaticCode?
        var requirement: SecRequirement?
        var text: CFString?
        if SecCodeCopySelf([], &code) == errSecSuccess, let code,
           SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
           SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess, let requirement {
            _ = SecRequirementCopyString(requirement, [], &text)
        }
        return Identity(version: version, requirement: text as String?)
    }

    static func state(defaults: UserDefaults) -> State? {
        defaults.data(forKey: stateKey).flatMap { try? JSONDecoder().decode(State.self, from: $0) }
    }

    static func plan(identity: Identity, existingUser: Bool, accessibility: Bool,
                     screenCapture: Bool, defaults: UserDefaults) -> Plan {
        let previous = state(defaults: defaults)
        // A recorded attempt, including failure, is never repeated on ordinary launches.
        guard previous?.identity != identity else { return Plan(identity: identity, services: []) }
        // Trust APIs describe this running executable, while Settings can display
        // a stale enabled entry. Never revoke a grant already valid for this process,
        // even if the version, signature, or copy of the app changed.
        let updating = previous != nil || existingUser
        var services: [String] = []
        if updating {
            if !accessibility { services.append("Accessibility") }
            if !screenCapture { services.append("ScreenCapture") }
        }
        return Plan(identity: identity, services: services)
    }

    /// Checkpoint before invoking tccutil so a crash cannot create a reset/relaunch loop.
    static func checkpoint(_ plan: Plan, defaults: UserDefaults,
                           persist: () -> Bool) throws {
        guard state(defaults: defaults)?.identity != plan.identity else { return }
        let oldState = defaults.object(forKey: stateKey)
        let oldPending = defaults.object(forKey: pendingKey)
        let oldStep = defaults.object(forKey: AppDefaults.Keys.welcomeStep)
        let value = State(identity: plan.identity, attemptedServices: plan.services, failedServices: [])
        defaults.set(try JSONEncoder().encode(value), forKey: stateKey)
        if !plan.services.isEmpty {
            defaults.set(true, forKey: pendingKey)
            defaults.set(2, forKey: AppDefaults.Keys.welcomeStep)
        }
        guard persist() else {
            defaults.set(oldState, forKey: stateKey)
            defaults.set(oldPending, forKey: pendingKey)
            defaults.set(oldStep, forKey: AppDefaults.Keys.welcomeStep)
            throw CocoaError(.fileWriteUnknown)
        }
    }

    static func finish(_ plan: Plan, failures: [String], defaults: UserDefaults) {
        guard state(defaults: defaults)?.identity == plan.identity else { return }
        let value = State(identity: plan.identity, attemptedServices: plan.services, failedServices: failures)
        defaults.set(try? JSONEncoder().encode(value), forKey: stateKey)
        defaults.synchronize()
    }

    static func completeAuthorization(defaults: UserDefaults) {
        defaults.removeObject(forKey: pendingKey)
    }
}

/// No shell interpolation, no `reset All`, and no access to the TCC database.
enum PermissionReset {
    static func run(executable: String, arguments: [String], timeout: TimeInterval = 10) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            let deadline = Date().addingTimeInterval(timeout)
            while task.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
            if task.isRunning { task.terminate(); return false }
            return task.terminationStatus == 0
        } catch { return false }
    }

    static func perform(services: [String], bundleID: String, appPath: String,
                        isGranted: (String) -> Bool = { _ in false },
                        run: (String, [String]) -> Bool = { run(executable: $0, arguments: $1) }) -> [String] {
        guard bundleID == "com.sonianmu.yisi", appPath.hasSuffix(".app"),
              services.allSatisfy({ ["Accessibility", "ScreenCapture"].contains($0) }) else { return services }
        // A manually replaced bundle may not yet be known to LaunchServices.
        let registered = run("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister", ["-f", appPath])
        guard registered else { return services }
        return services.filter { service in
            // Authorization can change while application registration is running.
            guard !isGranted(service) else { return false }
            return !run("/usr/bin/tccutil", ["reset", service, bundleID])
        }
    }
}
