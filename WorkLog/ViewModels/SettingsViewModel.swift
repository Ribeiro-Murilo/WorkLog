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
    var invoiceIssuerName: String = ""
    var invoiceIssuerDetails: String = ""
    var includeLogoInPDF: Bool = false
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

    @discardableResult
    func load() -> Bool {
        do {
            let settings = try settingsRepository.current()
            let bindings = try shortcutBindingRepository.fetchAll()
                .sorted { $0.action.displayName < $1.action.displayName }
            launchAtLogin = settings.launchAtLogin
            idleTimeoutMinutes = settings.idleTimeoutMinutes
            showSeconds = settings.showSeconds
            theme = settings.theme
            timeFormat = settings.timeFormat
            displayMode = settings.displayMode
            invoiceIssuerName = settings.invoiceIssuerName
            invoiceIssuerDetails = settings.invoiceIssuerDetails
            includeLogoInPDF = settings.includeLogoInPDF
            shortcutBindings = bindings
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func reloadAfterBackupImport() {
        guard load() else {
            errorMessage = "O backup foi importado, mas não foi possível recarregar suas preferências.\n\n\(errorMessage ?? "Erro desconhecido")"
            return
        }

        idleDetectionService.updateIdleThreshold(minutes: idleTimeoutMinutes)
        var failures: [String] = []
        do {
            try launchAtLoginService.setEnabled(launchAtLogin)
        } catch {
            failures.append("Inicialização no macOS: \(error.localizedDescription)")
        }
        do {
            try shortcutsService.refreshBindings()
        } catch {
            failures.append("Atalhos: \(error.localizedDescription)")
        }
        if !failures.isEmpty {
            errorMessage = "O backup foi importado, mas não foi possível aplicar todas as preferências.\n\n\(failures.joined(separator: "\n"))"
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
            settings.includeLogoInPDF = includeLogoInPDF
            try settingsRepository.save(settings)

            try launchAtLoginService.setEnabled(launchAtLogin)
            idleDetectionService.updateIdleThreshold(minutes: idleTimeoutMinutes)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveIssuer() {
        do {
            let settings = try settingsRepository.current()
            settings.invoiceIssuerName = invoiceIssuerName
            settings.invoiceIssuerDetails = invoiceIssuerDetails
            try settingsRepository.save(settings)
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
