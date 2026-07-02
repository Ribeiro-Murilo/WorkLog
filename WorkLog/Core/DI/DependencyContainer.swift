import Foundation
import SwiftData

@MainActor
final class DependencyContainer {
    let modelContext: ModelContext

    let projectRepository: ProjectRepositoryProtocol
    let sessionRepository: SessionRepositoryProtocol
    let settingsRepository: SettingsRepositoryProtocol
    let shortcutBindingRepository: ShortcutBindingRepositoryProtocol

    let validationService: ValidationServiceProtocol
    let idleDetectionService: IdleDetectionServiceProtocol
    let timerService: TimerServiceProtocol
    let exportService: ExportServiceProtocol
    let launchAtLoginService: LaunchAtLoginServiceProtocol
    let shortcutsService: ShortcutsServiceProtocol
    let backupService: BackupServiceProtocol
    let displayModeManager: DisplayModeManager

    init(modelContext: ModelContext) {
        self.modelContext = modelContext

        let projectRepository = ProjectRepository(modelContext: modelContext)
        let sessionRepository = SessionRepository(modelContext: modelContext)
        let settingsRepository = SettingsRepository(modelContext: modelContext)
        let shortcutBindingRepository = ShortcutBindingRepository(modelContext: modelContext)

        self.projectRepository = projectRepository
        self.sessionRepository = sessionRepository
        self.settingsRepository = settingsRepository
        self.shortcutBindingRepository = shortcutBindingRepository

        let validationService = ValidationService()
        let idleDetectionService = IdleDetectionService(idleThresholdMinutes: 10)

        self.validationService = validationService
        self.idleDetectionService = idleDetectionService
        self.timerService = TimerService(
            sessionRepository: sessionRepository,
            projectRepository: projectRepository,
            validationService: validationService,
            idleDetectionService: idleDetectionService
        )
        self.exportService = ExportService()
        self.launchAtLoginService = LaunchAtLoginService()
        self.shortcutsService = ShortcutsService(repository: shortcutBindingRepository)
        self.backupService = BackupService(projectRepository: projectRepository, sessionRepository: sessionRepository)
        self.displayModeManager = DisplayModeManager(
            settingsRepository: settingsRepository,
            timerService: self.timerService
        )
    }

    static func live() -> DependencyContainer {
        DependencyContainer(modelContext: PersistenceController.shared.mainContext)
    }

    static func preview() -> DependencyContainer {
        DependencyContainer(modelContext: PersistenceController.preview().mainContext)
    }
}
