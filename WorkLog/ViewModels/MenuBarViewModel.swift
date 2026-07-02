import Foundation
import Observation

@MainActor
@Observable
final class MenuBarViewModel {
    private let timerService: TimerServiceProtocol
    private let projectRepository: ProjectRepositoryProtocol
    private let sessionRepository: SessionRepositoryProtocol
    private let settingsRepository: SettingsRepositoryProtocol

    private(set) var recentProjects: [Project] = []
    private(set) var favoriteProjects: [Project] = []
    private(set) var todayTotal: TimeInterval = 0
    var errorMessage: String?

    var activeProject: Project? { timerService.activeProject }
    var isRunning: Bool { timerService.isRunning }
    var elapsed: TimeInterval { timerService.elapsed }

    var menuBarTitle: String? {
        guard isRunning, let project = activeProject else { return nil }
        let showSeconds = (try? settingsRepository.current().showSeconds) ?? true
        return "\(project.name) • \(elapsed.compactMenuBarString(showSeconds: showSeconds))"
    }

    init(
        timerService: TimerServiceProtocol,
        projectRepository: ProjectRepositoryProtocol,
        sessionRepository: SessionRepositoryProtocol,
        settingsRepository: SettingsRepositoryProtocol
    ) {
        self.timerService = timerService
        self.projectRepository = projectRepository
        self.sessionRepository = sessionRepository
        self.settingsRepository = settingsRepository
        reload()
    }

    func reload() {
        do {
            let allProjects = try projectRepository.fetchAll(includeArchived: false)
            favoriteProjects = allProjects.filter { $0.isFavorite }

            let recentSessions = try sessionRepository.fetchRecent(limit: 20)
            var seen = Set<UUID>()
            var recents: [Project] = []
            for session in recentSessions {
                guard let project = session.project, !seen.contains(project.id) else { continue }
                seen.insert(project.id)
                recents.append(project)
                if recents.count >= 5 { break }
            }
            recentProjects = recents

            let calendar = Calendar.current
            let dayInterval = calendar.dateInterval(of: .day, for: .now) ?? DateInterval(start: .now, end: .now)
            let todaySessions = try sessionRepository.fetchSessions(in: dayInterval)
            todayTotal = todaySessions.reduce(0) { $0 + $1.durationSeconds }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func start(project: Project) {
        do {
            try timerService.start(project: project)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func pause() {
        do {
            try timerService.pause()
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
