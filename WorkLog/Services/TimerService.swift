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
        elapsed = Date.now.timeIntervalSince(session.startTime)
        startTicking()
    }

    func start(project: Project) throws {
        try closeCurrentRunningSession(status: .paused)

        let session = Session(
            project: project,
            date: .now,
            startTime: .now,
            category: project.category,
            status: .running
        )
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
            latest = try sessionRepository.fetchAll(for: persistedProject).first
        } else {
            guard !isRunning, try sessionRepository.fetchActiveSession() == nil else { return nil }
            latest = try sessionRepository.fetchRecent(limit: 1).first
        }
        guard let latest, latest.status == .paused, latest.endTime != nil,
              let projectID = latest.project?.id,
              let persistedProject = try projectRepository.fetch(by: projectID),
              !persistedProject.isArchived else { return nil }
        return latest
    }

    func resume() throws {
        guard let session = try resumableSession(for: nil), let project = session.project else { return }
        try start(project: project)
    }

    func resume(project: Project) throws {
        guard let session = try resumableSession(for: project), let project = session.project else { return }
        // Um intervalo iniciado por outra superfície precisa ser fechado antes da troca.
        // O comando contextual preserva a mesma auto-pausa de Iniciar.
        activeSession = try sessionRepository.fetchActiveSession()
        activeProject = activeSession?.project
        try start(project: project)
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
        guard let session = activeSession else { return }
        let now = Date.now
        session.endTime = now
        session.durationSeconds = now.timeIntervalSince(session.startTime)
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
                self.elapsed = Date.now.timeIntervalSince(session.startTime)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }
}
