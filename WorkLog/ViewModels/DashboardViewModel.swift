import Foundation
import Observation

@MainActor
@Observable
final class DashboardViewModel {
    private let projectRepository: ProjectRepositoryProtocol
    private let sessionRepository: SessionRepositoryProtocol

    private(set) var todayTotal: TimeInterval = 0
    private(set) var weekTotal: TimeInterval = 0
    private(set) var monthTotal: TimeInterval = 0
    private(set) var allTimeTotal: TimeInterval = 0
    private(set) var activeProjectsCount: Int = 0
    private(set) var archivedProjectsCount: Int = 0
    private(set) var recentSessions: [Session] = []
    private(set) var mostUsedProjects: [(project: Project, total: TimeInterval)] = []
    private(set) var timeByCategory: [(category: ProjectCategory, total: TimeInterval)] = []
    private(set) var timeByClient: [(client: String, total: TimeInterval)] = []
    private(set) var timeByProject: [(project: Project, total: TimeInterval)] = []
    var errorMessage: String?

    init(projectRepository: ProjectRepositoryProtocol, sessionRepository: SessionRepositoryProtocol) {
        self.projectRepository = projectRepository
        self.sessionRepository = sessionRepository
        reload()
    }

    func reload() {
        do {
            let allProjects = try projectRepository.fetchAll(includeArchived: true)
            activeProjectsCount = allProjects.filter { !$0.isArchived }.count
            archivedProjectsCount = allProjects.filter { $0.isArchived }.count

            let closedStatuses: Set<SessionStatus> = [.completed, .paused]
            let allSessions = try sessionRepository.fetchAll(for: nil).filter { closedStatuses.contains($0.status) }
            allTimeTotal = allSessions.reduce(0) { $0 + $1.durationSeconds }

            let calendar = Calendar.current
            let now = Date.now
            let dayInterval = calendar.dateInterval(of: .day, for: now) ?? DateInterval(start: now, end: now)
            let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now) ?? dayInterval
            let monthInterval = calendar.dateInterval(of: .month, for: now) ?? dayInterval

            todayTotal = allSessions.filter { dayInterval.contains($0.startTime) }.reduce(0) { $0 + $1.durationSeconds }
            weekTotal = allSessions.filter { weekInterval.contains($0.startTime) }.reduce(0) { $0 + $1.durationSeconds }
            monthTotal = allSessions.filter { monthInterval.contains($0.startTime) }.reduce(0) { $0 + $1.durationSeconds }

            recentSessions = try sessionRepository.fetchRecent(limit: 10)

            let projectGroups = Dictionary(grouping: allSessions, by: { $0.project?.id })
            var usage: [(project: Project, total: TimeInterval)] = []
            for (_, sessions) in projectGroups {
                guard let project = sessions.first?.project else { continue }
                usage.append((project, sessions.reduce(0) { $0 + $1.durationSeconds }))
            }
            usage.sort { $0.total > $1.total }
            mostUsedProjects = usage
            timeByProject = usage

            let categoryGroups = Dictionary(grouping: allSessions, by: { $0.category })
            timeByCategory = categoryGroups
                .map { (category: $0.key, total: $0.value.reduce(0) { $0 + $1.durationSeconds }) }
                .sorted { $0.total > $1.total }

            let clientGroups = Dictionary(grouping: allSessions, by: { $0.project?.client ?? "—" })
            timeByClient = clientGroups
                .map { (client: $0.key, total: $0.value.reduce(0) { $0 + $1.durationSeconds }) }
                .sorted { $0.total > $1.total }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
