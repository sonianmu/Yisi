import Foundation

/// Owned by UpdateManager and configured on the main thread.
final class AutomaticUpdateScheduler {
    static let interval: TimeInterval = 6 * 60 * 60
    typealias Schedule = (TimeInterval, @escaping () -> Void) -> () -> Void

    private let check: () -> Void
    private let schedule: Schedule
    private var cancel: (() -> Void)?
    private var generation = 0
    private(set) var isEnabled = false

    init(check: @escaping () -> Void, schedule: @escaping Schedule = AutomaticUpdateScheduler.scheduleTimer) {
        self.check = check
        self.schedule = schedule
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        generation += 1
        cancel?()
        cancel = nil
        guard enabled else { return }
        let scheduledGeneration = generation
        cancel = schedule(Self.interval) { [weak self] in
            guard let self, self.isEnabled, self.generation == scheduledGeneration else { return }
            self.check()
        }
    }

    deinit { cancel?() }

    private static func scheduleTimer(interval: TimeInterval, check: @escaping () -> Void) -> () -> Void {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in check() }
        RunLoop.main.add(timer, forMode: .common)
        return { timer.invalidate() }
    }
}
