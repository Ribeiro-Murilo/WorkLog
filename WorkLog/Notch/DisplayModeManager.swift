import AppKit
import SwiftUI
import Observation

/// Decide se o app aparece na barra de menu ou no notch, respeitando a preferência do
/// usuário mas caindo para a barra de menu quando a tela atual não tem notch físico.
@MainActor
@Observable
final class DisplayModeManager {
    private let settingsRepository: SettingsRepositoryProtocol
    private let notchController = NotchWindowController()

    private(set) var isMenuBarVisible = true

    init(settingsRepository: SettingsRepositoryProtocol) {
        self.settingsRepository = settingsRepository
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func configureNotchContent(@ViewBuilder content: @escaping () -> some View) {
        notchController.content = { _ in AnyView(content()) }
    }

    func refresh() {
        let preferredMode = (try? settingsRepository.current().displayMode) ?? .menuBar
        let effectiveMode: AppDisplayMode = (preferredMode == .notch && NotchGeometry.hasAnyNotch)
            ? .notch
            : .menuBar

        switch effectiveMode {
        case .menuBar:
            isMenuBarVisible = true
            notchController.dismiss()
        case .notch:
            isMenuBarVisible = false
            if let screen = NotchGeometry.primaryNotchScreen {
                notchController.present(on: screen)
            } else {
                isMenuBarVisible = true
            }
        }
    }

    @objc private func screenParametersChanged() {
        refresh()
    }
}
