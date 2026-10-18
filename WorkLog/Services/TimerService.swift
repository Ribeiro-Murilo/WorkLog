import Foundation
import Observation

@MainActor
protocol TimerServiceProtocol: AnyObject {
    var activeSession: Session? { get }
    var activeProject: Project? { get }
    var elapsed: TimeInterval { get }
    var isRunning: Bool { get }

    func start(project: Project) throws
    func pause() throws
    func resume() throws
    func resume(project: Project) throws
    func resumableSession(for project: Project?) throws -> Session?
    func stop() throws
    func addManualSession(project: Project, startTime: Date, endTime: Date, note: String) throws
}

@MainActor
@Observable
final class TimerService: TimerServiceProtocol {
    private(set) var activeSession: Session?
    private(set) var activeProject: Project?
    private(set) var elapsed: TimeInterval = 0

    var isRunning: Bool { activeSession != nil }

    private let sessionRepository: SessionRepositoryProtocol
    private let projectRepository: ProjectRepositoryProtocol
    private let validationService: ValidationServiceProtocol
    private let idleDetectionService: IdleDetectionServiceProtocol
    private var tickTask: Task<Void, Never>?

    init(
        sessionRepository: SessionRepositoryProtocol,
        projectRepository: ProjectRepositoryProtocol,
        validationService: ValidationServiceProtocol = ValidationService(),
        idleDetectionService: IdleDetectionServiceProtocol
    ) {
        self.sessionRepository = sessionRepository
        self.projectRepository = projectRepository
        self.validationService = validationService
        self.idleDetectionService = idleDetectionService

        restoreActiveSessionIfNeeded()

        self.idleDetectionService.onShouldAutoPause = { [weak self] in
            try? self?.pause()
        }
    }

    private func restoreActiveSessionIfNeeded() {
        guard let session = try? sessionRepository.fetchActiveSession() else { return }
        activeSession = session
        activeProject = session.project
        elapsed = session.elapsedDuration()
        startTicking()
    }

    func start(project: Project) throws {
        try closeCurrentRunningSession(status: .paused)

        let now = Date.now
        let session = Session(
            project: project,
            date: now,
            startTime: now,
            category: project.category,
            status: .running
        )
        session.workPeriods = [SessionWorkPeriod(start: now, end: nil)]
        try sessionRepository.insert(session)

        activeSession = session
        activeProject = project
        elapsed = 0
        startTicking()
    }

    func pause() throws {
        try closeCurrentRunningSession(status: .paused)
        stopTicking()
    }

    /// A pausa só continua enquanto for o último intervalo no escopo solicitado.
    /// Consultar o repositório também protege atalhos e painéis que ficaram abertos.
    func resumableSession(for project: Project?) throws -> Session? {
        // Fetches não notificam Observation quando uma sessão entra/sai do resultado.
        // A revisão publica as mudanças de coleção para os controles já visíveis.
        _ = sessionRepository.dataRevision
        let latest: Session?
        if let project {
            guard let persistedProject = try projectRepository.fetch(by: project.id),
                  !persistedProject.isArchived else { return nil }
            latest = try sessionRepository.fetchAll(for: persistedProject).max { $0.latestActivity < $1.latestActivity }
        } else {
            guard !isRunning, try sessionRepository.fetchActiveSession() == nil else { return nil }
            latest = try sessionRepository.fetchAll(for: nil).max { $0.latestActivity < $1.latestActivity }
        }
        guard let latest, latest.status == .paused, latest.endTime != nil,
              let projectID = latest.project?.id,
              let persistedProject = try projectRepository.fetch(by: projectID),
              !persistedProject.isArchived else { return nil }
        return latest
    }

    func resume() throws {
        guard let session = try resumableSession(for: nil) else { return }
        try resume(session: session)
    }

    func resume(project: Project) throws {
        guard let session = try resumableSession(for: project) else { return }
        try resume(session: session)
    }

    private func resume(session: Session) throws {
        // Materializa o legado antes de remover seu fechamento, preservando a duração.
        var periods = session.workPeriods
        let accumulated = periods.reduce(0) { total, period in
            total + max(0, (period.end ?? period.start).timeIntervalSince(period.start))
        }
        try closeCurrentRunningSession(status: .paused)
        let now = Date.now
        periods.append(SessionWorkPeriod(start: now, end: nil))
        session.workPeriods = periods
        session.durationSeconds = accumulated
        session.endTime = nil
        session.status = .running
        try sessionRepository.update(session)
        activeSession = session
        activeProject = session.project
        elapsed = session.elapsedDuration(at: now)
        startTicking()
    }

    func stop() throws {
        try closeCurrentRunningSession(status: .completed)
        stopTicking()
    }

    func addManualSession(project: Project, startTime: Date, endTime: Date, note: String) throws {
        try validationService.validateSessionFields(project: project, startTime: startTime, endTime: endTime)
        guard try !sessionRepository.hasOverlap(start: startTime, end: endTime, excluding: nil) else {
            throw ValidationError.overlappingSession
        }
        let session = Session(
            project: project,
            date: startTime,
            startTime: startTime,
            endTime: endTime,
            durationSeconds: endTime.timeIntervalSince(startTime),
            note: note,
            category: project.category,
            status: .completed
        )
        try sessionRepository.insert(session)
    }

    private func closeCurrentRunningSession(status: SessionStatus) throws {
        guard let session = try sessionRepository.fetchActiveSession() ?? activeSession,
              session.status == .running else { return }
        let now = Date.now
        var periods = session.workPeriods
        for index in periods.indices where periods[index].end == nil {
            periods[index].end = max(now, periods[index].start)
        }
        session.workPeriods = periods
        session.endTime = now
        session.durationSeconds = periods.reduce(0) { total, period in
            total + max(0, (period.end ?? period.start).timeIntervalSince(period.start))
        }
        session.status = status
        try sessionRepository.update(session)
        activeSession = nil
        activeProject = nil
        elapsed = 0
    }

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let session = self.activeSession else { return }
                self.elapsed = session.elapsedDuration()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }
}
