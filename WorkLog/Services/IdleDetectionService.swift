import Foundation
import AppKit
import CoreGraphics

@MainActor
protocol IdleDetectionServiceProtocol: AnyObject {
    var onShouldAutoPause: (() -> Void)? { get set }
    func start()
    func stop()
    func updateIdleThreshold(minutes: Int)
}

@MainActor
final class IdleDetectionService: IdleDetectionServiceProtocol {
    var onShouldAutoPause: (() -> Void)?

    private var idleThresholdSeconds: TimeInterval
    private var pollTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var didFireForCurrentIdlePeriod = false

    init(idleThresholdMinutes: Int) {
        self.idleThresholdSeconds = TimeInterval(idleThresholdMinutes * 60)
    }

    func updateIdleThreshold(minutes: Int) {
        idleThresholdSeconds = TimeInterval(minutes * 60)
    }

    func start() {
        registerSystemNotifications()
        startPolling()
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach { center.removeObserver($0) }
        observers.removeAll()
    }

    private func registerSystemNotifications() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification,
        ]
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.onShouldAutoPause?()
            }
            observers.append(token)
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self else { return }
                let idleSeconds = Self.secondsSinceLastUserInput()
                if idleSeconds >= self.idleThresholdSeconds {
                    if !self.didFireForCurrentIdlePeriod {
                        self.didFireForCurrentIdlePeriod = true
                        self.onShouldAutoPause?()
                    }
                } else {
                    self.didFireForCurrentIdlePeriod = false
                }
            }
        }
    }

    private static func secondsSinceLastUserInput() -> TimeInterval {
        guard let anyEventType = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyEventType)
    }
}
