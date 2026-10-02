import AppKit
import Testing
@testable import WorkLog

@MainActor
struct NotchLifecycleObserverTests {
    @Test(arguments: [
        NSWorkspace.didWakeNotification,
        NSWorkspace.screensDidWakeNotification,
        NSWorkspace.sessionDidBecomeActiveNotification
    ])
    func workspaceReturnRefreshesNotch(notification: Notification.Name) {
        let center = NotificationCenter()
        var refreshCount = 0
        let observer = NotchLifecycleObserver(notificationCenter: center) {
            refreshCount += 1
        }

        withExtendedLifetime(observer) {
            center.post(name: notification, object: nil)
        }

        #expect(refreshCount == 1)
    }

    @Test func focusAndSleepEventsDoNotRefreshNotch() {
        let center = NotificationCenter()
        var refreshCount = 0
        let observer = NotchLifecycleObserver(notificationCenter: center) {
            refreshCount += 1
        }

        withExtendedLifetime(observer) {
            for notification in [
                NSWorkspace.activeSpaceDidChangeNotification,
                NSApplication.didBecomeActiveNotification,
                NSWorkspace.willSleepNotification,
                NSWorkspace.screensDidSleepNotification,
                NSWorkspace.sessionDidResignActiveNotification
            ] {
                center.post(name: notification, object: nil)
            }
        }

        #expect(refreshCount == 0)
    }

    @Test func deallocationUnregistersWorkspaceNotifications() {
        let center = LifecycleNotificationCenter()
        var refreshCount = 0
        var observer: NotchLifecycleObserver? = NotchLifecycleObserver(notificationCenter: center) {
            refreshCount += 1
        }
        weak let weakObserver = observer

        #expect(center.registeredCount == 3)
        observer = nil

        #expect(weakObserver == nil)
        #expect(center.registeredCount == 0)
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(refreshCount == 0)
    }
}

/// Delivers real notifications while exposing whether the subscription resources
/// have been removed, even when their callbacks would otherwise be harmless.
private final class LifecycleNotificationCenter: NotificationCenter, @unchecked Sendable {
    private var registeredObservers: Set<ObjectIdentifier> = []
    var registeredCount: Int { registeredObservers.count }

    override func addObserver(
        forName name: Notification.Name?,
        object obj: Any?,
        queue: OperationQueue?,
        using block: @escaping @Sendable (Notification) -> Void
    ) -> NSObjectProtocol {
        let token = super.addObserver(forName: name, object: obj, queue: queue, using: block)
        registeredObservers.insert(ObjectIdentifier(token as AnyObject))
        return token
    }

    override func removeObserver(_ observer: Any) {
        registeredObservers.remove(ObjectIdentifier(observer as AnyObject))
        super.removeObserver(observer)
    }
}
