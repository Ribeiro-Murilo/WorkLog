import Foundation
import Observation

@MainActor
@Observable
final class SettingsViewModel {
    private let settingsRepository: SettingsRepositoryProtocol
    private let launchAtLoginService: LaunchAtLoginServiceProtocol
    private let idleDetectionService: IdleDetectionServiceProtocol
    private let shortcutBindingRepository: ShortcutBindingRepositoryProtocol
    private let shortcutsService: ShortcutsServiceProtocol

    var launchAtLogin: Bool = true
    var idleTimeoutMinutes: Int = 10
    var showSeconds: Bool = true
    var theme: AppTheme = .system
    var timeFormat: TimeFormatPreference = .twentyFourHour
    var displayMode: AppDisplayMode = .menuBar
    private(set) var shortcutBindings: [ShortcutBinding] = []
    var errorMessage: String?

    init(
        settingsRepository: SettingsRepositoryProtocol,
        launchAtLoginService: LaunchAtLoginServiceProtocol,
        idleDetectionService: IdleDetectionServiceProtocol,
        shortcutBindingRepository: ShortcutBindingRepositoryProtocol,
        shortcutsService: ShortcutsServiceProtocol
    ) {
        self.settingsRepository = settingsRepository
        self.launchAtLoginService = launchAtLoginService
        self.idleDetectionService = idleDetectionService
        self.shortcutBindingRepository = shortcutBindingRepository
        self.shortcutsService = shortcutsService
        load()
    }

    func load() {
        do {
            let settings = try settingsRepository.current()
            launchAtLogin = settings.launchAtLogin
            idleTimeoutMinutes = settings.idleTimeoutMinutes
            showSeconds = settings.showSeconds
            theme = settings.theme
            timeFormat = settings.timeFormat
            displayMode = settings.displayMode
            shortcutBindings = try shortcutBindingRepository.fetchAll()
                .sorted { $0.action.displayName < $1.action.displayName }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save() {
        do {
            let settings = try settingsRepository.current()
            settings.launchAtLogin = launchAtLogin
            settings.idleTimeoutMinutes = idleTimeoutMinutes
            settings.showSeconds = showSeconds
            settings.theme = theme
            settings.timeFormat = timeFormat
            settings.displayMode = displayMode
            try settingsRepository.save(settings)

            try launchAtLoginService.setEnabled(launchAtLogin)
            idleDetectionService.updateIdleThreshold(minutes: idleTimeoutMinutes)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateShortcut(action: ShortcutAction, keyCombo: KeyCombo) {
        do {
            try shortcutsService.updateBinding(action: action, keyCombo: keyCombo)
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
