import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var onDidFinishLaunching: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        onDidFinishLaunching?()
    }
}
