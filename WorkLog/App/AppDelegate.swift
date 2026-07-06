import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var onDidFinishLaunching: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        onDidFinishLaunching?()
    }

    /// Com o ícone no Dock, fechar a janela do Dashboard não deve encerrar o app —
    /// ele continua rodando em segundo plano (menu bar / notch).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
