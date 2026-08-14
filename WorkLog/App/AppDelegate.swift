import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var onDidFinishLaunching: (() -> Void)?
    var storageMigrationNotice: StorageMigrationNotice?

    func applicationDidFinishLaunching(_ notification: Notification) {
        onDidFinishLaunching?()
        if let storageMigrationNotice {
            showStorageMigrationNotice(storageMigrationNotice)
        }
    }

    func showStorageMigrationNotice(_ notice: StorageMigrationNotice) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = notice.title
        alert.informativeText = notice.message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Com o ícone no Dock, fechar a janela do Dashboard não deve encerrar o app —
    /// ele continua rodando em segundo plano (menu bar / notch).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
