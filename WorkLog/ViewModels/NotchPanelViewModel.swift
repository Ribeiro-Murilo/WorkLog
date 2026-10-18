import Foundation
import Observation

@MainActor
@Observable
final class NotchPanelViewModel {
    enum State { case running, paused, idle }

    private let timerService: TimerServiceProtocol
    private let projectRepository: ProjectRepositoryProtocol
    private let sessionRepository: SessionRepositoryProtocol
    private let settingsRepository: SettingsRepositoryProtocol

    private var projects: [Project] = []
    private var recentProjectIDs: [UUID] = []
    private var pausedSession: Session?
    private var settings: AppSettings?
    private(set) var todayTotal: TimeInterval = 0
    var query = ""
    var errorMessage: String?

    var isRunning: Bool { timerService.isRunning }
    private var resumableSession: Session? {
        guard let pausedSession, pausedSession.status == .paused,
              let project = pausedSession.project, !project.isArchived else { return nil }
        return pausedSession
    }
    var state: State { isRunning ? .running : resumableSession == nil ? .idle : .paused }
    var project: Project? { isRunning ? timerService.activeProject : resumableSession?.project }
    var elapsed: TimeInterval { isRunning ? timerService.elapsed : resumableSession?.durationSeconds ?? 0 }
    var elapsedFormatted: String { elapsed.formattedClock(showSeconds: settings?.showSeconds ?? true) }

    var visibleProjects: [Project] {
        let available = projects.filter { !$0.isArchived && $0.id != timerService.activeProject?.id }
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard search.isEmpty else {
            return available.filter {
                $0.name.localizedStandardContains(search) || $0.client.localizedStandardContains(search)
            }
        }
        let byID = Dictionary(available.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let preferred = available.filter(\.isFavorite) + recentProjectIDs.compactMap { byID[$0] }
        var seen = Set<UUID>()
        let unique = preferred.filter { seen.insert($0.id).inserted }
        return unique.isEmpty ? available : unique
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
            let loadedProjects = try projectRepository.fetchAll(includeArchived: false)
            let sessions = try sessionRepository.fetchRecent(limit: 50)
            let settings = try settingsRepository.current()
            let day = Calendar.current.dateInterval(of: .day, for: .now)
                ?? DateInterval(start: .now, end: .now)
            let todaySessions = try sessionRepository.fetchSessions(in: day)
            projects = loadedProjects
            recentProjectIDs = sessions.compactMap { $0.project?.id }
            pausedSession = try timerService.resumableSession(for: nil)
            self.settings = settings
            todayTotal = todaySessions.reduce(0) { $0 + $1.recordedDuration(in: day) }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func start(project: Project) { perform { try timerService.start(project: project) } }
    func pause() { perform { try timerService.pause() } }
    func stop() { perform { try timerService.stop() } }
    func resume() {
        guard !isRunning else { return }
        let displayedSessionID = resumableSession?.id
        // Dashboard e registros manuais podem mudar o último intervalo enquanto
        // o painel está fixado. Atualize a sessão exibida antes de retomar outra sessão.
        reload()
        guard errorMessage == nil, let resumableSession,
              resumableSession.id == displayedSessionID else { return }
        perform { try timerService.resume() }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
