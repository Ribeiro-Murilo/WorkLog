import Foundation
import SwiftData
import Testing
@testable import WorkLog

@MainActor
struct SettingsSyncTests {
    @Test func restoredBackupReplacesOpenSettingsCacheAndActivePreferences() throws {
        let context = try makeSyncRecordContext()
        let restored = AppSettings(
            launchAtLogin: false,
            idleTimeoutMinutes: 60,
            showSeconds: false,
            theme: .dark,
            timeFormat: .twelveHour,
            displayMode: .notch,
            invoiceIssuerName: "Restored issuer",
            invoiceIssuerDetails: "Restored details"
        )
        restored.includeLogoInPDF = true
        context.insert(restored)
        context.insert(ShortcutBinding(action: .startTimer, keyCombo: KeyCombo(keyCode: 7, modifiers: 256)))
        context.insert(ShortcutBinding(action: .pauseTimer, keyCombo: KeyCombo(keyCode: 9, modifiers: 256), isEnabled: false))
        try context.save()
        let backupService = BackupService(modelContext: context)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        try backupService.exportBackup(to: url)

        try context.delete(model: AppSettings.self)
        try context.delete(model: ShortcutBinding.self)
        context.insert(AppSettings())
        context.insert(ShortcutBinding(action: .startTimer, keyCombo: KeyCombo(keyCode: 1, modifiers: 128)))
        context.insert(ShortcutBinding(action: .pauseTimer, keyCombo: KeyCombo(keyCode: 35, modifiers: 128)))
        try context.save()
        let repository = SettingsRepository(modelContext: context)
        let shortcutRepository = ShortcutBindingRepository(modelContext: context)
        let launchService = SyncSettingsLaunchService()
        let idleService = SyncSettingsIdleService()
        let shortcutsService = RestoredSettingsShortcutsService(repository: shortcutRepository)
        var starts = 0
        var pauses = 0
        try shortcutsService.register(action: .startTimer) { starts += 1 }
        try shortcutsService.register(action: .pauseTimer) { pauses += 1 }
        let viewModel = SettingsViewModel(
            settingsRepository: repository,
            launchAtLoginService: launchService,
            idleDetectionService: idleService,
            shortcutBindingRepository: shortcutRepository,
            shortcutsService: shortcutsService
        )
        #expect(viewModel.launchAtLogin)
        #expect(viewModel.idleTimeoutMinutes == 10)

        try backupService.importBackup(from: url)
        viewModel.reloadAfterBackupImport()

        #expect(!viewModel.launchAtLogin)
        #expect(viewModel.idleTimeoutMinutes == 60)
        #expect(!viewModel.showSeconds)
        #expect(viewModel.theme == .dark)
        #expect(viewModel.timeFormat == .twelveHour)
        #expect(viewModel.displayMode == .notch)
        #expect(viewModel.invoiceIssuerName == "Restored issuer")
        #expect(viewModel.invoiceIssuerDetails == "Restored details")
        #expect(viewModel.includeLogoInPDF)
        #expect(!launchService.isEnabled)
        #expect(idleService.thresholdMinutes == 60)
        shortcutsService.press(KeyCombo(keyCode: 7, modifiers: 256))
        #expect(starts == 1)
        shortcutsService.press(KeyCombo(keyCode: 1, modifiers: 128))
        #expect(starts == 1)
        shortcutsService.press(KeyCombo(keyCode: 35, modifiers: 128))
        shortcutsService.press(KeyCombo(keyCode: 9, modifiers: 256))
        #expect(starts == 1)
        #expect(pauses == 0)
        #expect(try shortcutRepository.fetch(for: .pauseTimer)?.isEnabled == false)

        // A later edit in the already-open view must keep the restored preferences.
        viewModel.showSeconds = true
        viewModel.save()
        let saved = try repository.current()
        #expect(!saved.launchAtLogin)
        #expect(saved.idleTimeoutMinutes == 60)
        #expect(saved.theme == .dark)
        #expect(saved.timeFormat == .twelveHour)
        #expect(saved.displayMode == .notch)
        #expect(saved.includeLogoInPDF)
        #expect(saved.invoiceIssuerName == "Restored issuer")
        #expect(viewModel.errorMessage == nil)
    }

    @Test func importedBackupStaysRestoredWhenLaunchRegistrationFails() throws {
        let context = try makeSyncRecordContext()
        context.insert(AppSettings(launchAtLogin: false, idleTimeoutMinutes: 60, theme: .dark))
        try context.save()
        let backupService = BackupService(modelContext: context)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        try backupService.exportBackup(to: url)
        try context.delete(model: AppSettings.self)
        context.insert(AppSettings())
        try context.save()
        let repository = SettingsRepository(modelContext: context)
        let launchService = SyncSettingsLaunchService()
        launchService.failure = NSError(domain: "SettingsSyncTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Login registration rejected"])
        let idleService = SyncSettingsIdleService()
        let viewModel = SettingsViewModel(
            settingsRepository: repository,
            launchAtLoginService: launchService,
            idleDetectionService: idleService,
            shortcutBindingRepository: ShortcutBindingRepository(modelContext: context),
            shortcutsService: SyncSettingsShortcutsService()
        )

        try backupService.importBackup(from: url)
        viewModel.reloadAfterBackupImport()

        let restored = try repository.current()
        #expect(!restored.launchAtLogin)
        #expect(restored.idleTimeoutMinutes == 60)
        #expect(restored.theme == .dark)
        #expect(!viewModel.launchAtLogin)
        #expect(viewModel.idleTimeoutMinutes == 60)
        #expect(idleService.thresholdMinutes == 60)
        #expect(viewModel.errorMessage?.contains("O backup foi importado") == true)
        #expect(viewModel.errorMessage?.contains("Login registration rejected") == true)
    }

    @Test func successfulReloadClearsPreviousReadFailure() {
        let repository = SyncSettingsRepository()
        let viewModel = makeViewModel(repository)
        repository.currentError = NSError(domain: "SettingsSyncTests", code: 2)
        viewModel.load()
        #expect(viewModel.errorMessage != nil)

        repository.currentError = nil
        repository.settings.idleTimeoutMinutes = 30
        viewModel.load()

        #expect(viewModel.idleTimeoutMinutes == 30)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func machinePreferenceSavePreservesIssuerImportedAfterOpeningSettings() {
        let repository = SyncSettingsRepository()
        repository.settings.invoiceIssuerName = "Original"
        repository.settings.invoiceIssuerDetails = "Original details"
        let viewModel = makeViewModel(repository)

        // An import changes the shared model while the settings view still has its old copy.
        repository.settings.invoiceIssuerName = "Imported issuer"
        repository.settings.invoiceIssuerDetails = "Imported details"
        viewModel.showSeconds = false
        viewModel.save()

        #expect(repository.settings.invoiceIssuerName == "Imported issuer")
        #expect(repository.settings.invoiceIssuerDetails == "Imported details")
        #expect(!repository.settings.showSeconds)
        #expect(repository.saveCount == 1)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func issuerSavePreservesMachinePreferencesAndInvoiceCounter() {
        let repository = SyncSettingsRepository()
        let viewModel = makeViewModel(repository)
        repository.settings.launchAtLogin = false
        repository.settings.idleTimeoutMinutes = 60
        repository.settings.showSeconds = false
        repository.settings.theme = .dark
        repository.settings.includeLogoInPDF = true
        repository.settings.lastInvoiceNumber = 42
        repository.settings.updatedAt = .distantPast
        viewModel.invoiceIssuerName = "Edited issuer"
        viewModel.invoiceIssuerDetails = "Edited details"

        viewModel.saveIssuer()

        #expect(repository.settings.invoiceIssuerName == "Edited issuer")
        #expect(repository.settings.invoiceIssuerDetails == "Edited details")
        #expect(!repository.settings.launchAtLogin)
        #expect(repository.settings.idleTimeoutMinutes == 60)
        #expect(!repository.settings.showSeconds)
        #expect(repository.settings.theme == .dark)
        #expect(repository.settings.includeLogoInPDF)
        #expect(repository.settings.lastInvoiceNumber == 42)
        #expect(repository.settings.updatedAt > .distantPast)
        #expect(repository.saveCount == 1)
        #expect(viewModel.errorMessage == nil)
    }

    private func makeViewModel(_ repository: SyncSettingsRepository) -> SettingsViewModel {
        SettingsViewModel(
            settingsRepository: repository,
            launchAtLoginService: SyncSettingsLaunchService(),
            idleDetectionService: SyncSettingsIdleService(),
            shortcutBindingRepository: SyncSettingsShortcutRepository(),
            shortcutsService: SyncSettingsShortcutsService()
        )
    }
}

@MainActor
private final class SyncSettingsRepository: SettingsRepositoryProtocol {
    let settings = AppSettings()
    var saveCount = 0
    var currentError: Error?
    func current() throws -> AppSettings {
        if let currentError { throw currentError }
        return settings
    }
    func save(_ settings: AppSettings) throws {
        settings.updatedAt = .now
        saveCount += 1
    }
}

private final class SyncSettingsLaunchService: LaunchAtLoginServiceProtocol {
    private(set) var isEnabled = true
    var failure: Error?
    func setEnabled(_ enabled: Bool) throws {
        if let failure { throw failure }
        isEnabled = enabled
    }
}

@MainActor
private final class SyncSettingsIdleService: IdleDetectionServiceProtocol {
    var onShouldAutoPause: (() -> Void)?
    private(set) var thresholdMinutes = 10
    func start() {}
    func stop() {}
    func updateIdleThreshold(minutes: Int) { thresholdMinutes = minutes }
}

@MainActor
private final class SyncSettingsShortcutRepository: ShortcutBindingRepositoryProtocol {
    func fetchAll() throws -> [ShortcutBinding] { [] }
    func fetch(for action: ShortcutAction) throws -> ShortcutBinding? { nil }
    func save(_ binding: ShortcutBinding) throws {}
    func upsert(action: ShortcutAction, keyCombo: KeyCombo, isEnabled: Bool) throws -> ShortcutBinding {
        ShortcutBinding(action: action, keyCombo: keyCombo, isEnabled: isEnabled)
    }
}

private final class SyncSettingsShortcutsService: ShortcutsServiceProtocol {
    func registerDefaultsIfNeeded() throws {}
    func register(action: ShortcutAction, handler: @escaping () -> Void) throws {}
    func updateBinding(action: ShortcutAction, keyCombo: KeyCombo) throws {}
    func refreshBindings() throws {}
    func unregisterAll() {}
}

@MainActor
private final class RestoredSettingsShortcutsService: ShortcutsServiceProtocol {
    private let repository: ShortcutBindingRepositoryProtocol
    private var handlers: [ShortcutAction: () -> Void] = [:]
    private var installed: [ShortcutAction: KeyCombo] = [:]

    init(repository: ShortcutBindingRepositoryProtocol) { self.repository = repository }
    func registerDefaultsIfNeeded() throws {}
    func register(action: ShortcutAction, handler: @escaping () -> Void) throws {
        handlers[action] = handler
        if let binding = try repository.fetch(for: action), binding.isEnabled {
            installed[action] = binding.keyCombo
        }
    }
    func updateBinding(action: ShortcutAction, keyCombo: KeyCombo) throws {
        _ = try repository.upsert(action: action, keyCombo: keyCombo, isEnabled: true)
        installed[action] = keyCombo
    }
    func refreshBindings() throws {
        unregisterAll()
        for action in handlers.keys {
            if let binding = try repository.fetch(for: action), binding.isEnabled {
                installed[action] = binding.keyCombo
            }
        }
    }
    func unregisterAll() { installed.removeAll() }
    func press(_ keyCombo: KeyCombo) {
        for (action, installedCombo) in installed where installedCombo == keyCombo {
            handlers[action]?()
        }
    }
}
