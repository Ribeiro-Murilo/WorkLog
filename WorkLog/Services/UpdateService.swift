import AppKit
import Sparkle

@MainActor
protocol UpdateServiceProtocol {
    var canCheckForUpdates: Bool { get }
    func checkForUpdates()
}

/// Encapsula o `SPUStandardUpdaterController` do Sparkle. A checagem é sempre manual
/// (disparada pelo botão em Configurações) — sem verificação automática em segundo plano.
@MainActor
final class UpdateService: UpdateServiceProtocol {
    private let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        controller.updater.automaticallyChecksForUpdates = false
    }

    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }

    func checkForUpdates() {
        // App acessório (`LSUIElement`): sem ativar a app, a janela de atualização do
        // Sparkle pode abrir sem foco, atrás de outras janelas.
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}
