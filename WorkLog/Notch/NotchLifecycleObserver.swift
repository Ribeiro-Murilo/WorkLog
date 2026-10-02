import AppKit

@MainActor
final class NotchLifecycleObserver {
    private let notificationCenter: NotificationCenter
    private let onRefresh: @MainActor () -> Void
    private var observers: [NSObjectProtocol] = []

    init(
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        onRefresh: @escaping @MainActor () -> Void
    ) {
        self.notificationCenter = notificationCenter
        self.onRefresh = onRefresh

        for notification in [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification
        ] {
            let token = notificationCenter.addObserver(
                forName: notification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.onRefresh()
                }
            }
            observers.append(token)
        }
    }

    isolated deinit {
        observers.forEach { notificationCenter.removeObserver($0) }
    }
}
