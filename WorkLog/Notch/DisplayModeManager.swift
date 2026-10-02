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
    @ObservationIgnored private var lifecycleObserver: NotchLifecycleObserver?
    @ObservationIgnored private var screenRecovery: NotchScreenRecovery?

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
        screenRecovery = NotchScreenRecovery(isScreenAvailable: {
            NotchGeometry.primaryNotchScreen != nil
        }) { [weak self] in
            self?.refresh()
        }
        lifecycleObserver = NotchLifecycleObserver { [weak self] in
            self?.refresh()
        }
        observeTimerRunning()
    }

    func configureNotchContent(
        @ViewBuilder expanded: @escaping () -> some View,
        @ViewBuilder collapsedTrailing: @escaping () -> some View
    ) {
        notchController.content = { [weak controller = notchController] isExpanded, notchWidth, notchHeight in
            AnyView(
                NotchContentView(
                    isExpanded: isExpanded,
                    notchWidth: notchWidth,
                    notchHeight: notchHeight,
                    onExpandedHeightChange: { [weak controller] height in
                        Task { @MainActor in
                            controller?.updateExpandedHeight(height)
                        }
                    }
                ) {
                    expanded()
                } collapsedTrailing: {
                    collapsedTrailing()
                }
            )
        }
    }

    func refresh() {
        let preferredMode = (try? settingsRepository.current().displayMode) ?? .menuBar
        let notchScreen = preferredMode == .notch ? NotchGeometry.primaryNotchScreen : nil
        let effectiveMode: AppDisplayMode = notchScreen != nil ? .notch : .menuBar

        switch effectiveMode {
        case .menuBar:
            isMenuBarVisible = true
            notchController.dismiss()
            if preferredMode == .notch {
                screenRecovery?.start()
            } else {
                screenRecovery?.stop()
            }
        case .notch:
            screenRecovery?.stop()
            isMenuBarVisible = false
            if let screen = notchScreen {
                updateTimerBadgeWidth()
                notchController.present(on: screen)
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
