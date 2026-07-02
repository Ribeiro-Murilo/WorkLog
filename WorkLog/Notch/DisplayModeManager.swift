import AppKit
import SwiftUI
import Observation

/// Decide se o app aparece na barra de menu ou no notch, respeitando a preferência do
/// usuário mas caindo para a barra de menu quando a tela atual não tem notch físico.
@MainActor
@Observable
final class DisplayModeManager {
    /// Largura reservada à direita do notch para o timer colapsado (cabe "H:MM:SS").
    private static let timerBadgeWidth: CGFloat = 84

    private let settingsRepository: SettingsRepositoryProtocol
    private let timerService: TimerServiceProtocol
    private let notchController = NotchWindowController()

    private(set) var isMenuBarVisible = true

    init(settingsRepository: SettingsRepositoryProtocol, timerService: TimerServiceProtocol) {
        self.settingsRepository = settingsRepository
        self.timerService = timerService
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        observeTimerRunning()
    }

    func configureNotchContent(
        @ViewBuilder expanded: @escaping () -> some View,
        @ViewBuilder collapsedTrailing: @escaping () -> some View
    ) {
        notchController.content = { isExpanded, notchWidth in
            AnyView(
                NotchContentView(isExpanded: isExpanded, notchWidth: notchWidth) {
                    expanded()
                } collapsedTrailing: {
                    collapsedTrailing()
                }
            )
        }
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
                updateTimerBadgeWidth()
                notchController.present(on: screen)
            } else {
                isMenuBarVisible = true
            }
        }
    }

    @objc private func screenParametersChanged() {
        refresh()
    }

    /// Reage ao início/fim do timer para alargar/estreitar o painel colapsado. O
    /// `onChange` do Observation dispara antes da mudança ser aplicada, por isso o
    /// valor é relido de forma assíncrona e a observação é re-armada.
    private func observeTimerRunning() {
        withObservationTracking {
            _ = timerService.isRunning
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.updateTimerBadgeWidth()
                self.observeTimerRunning()
            }
        }
    }

    private func updateTimerBadgeWidth() {
        notchController.collapsedTrailingWidth = timerService.isRunning ? Self.timerBadgeWidth : 0
    }
}
