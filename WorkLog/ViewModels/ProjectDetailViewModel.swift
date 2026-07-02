import Foundation
import Observation

@MainActor
@Observable
final class ProjectDetailViewModel {
    let project: Project

    private let sessionRepository: SessionRepositoryProtocol
    private let timerService: TimerServiceProtocol

    private(set) var sessions: [Session] = []
    var errorMessage: String?

    var isActiveProject: Bool { timerService.activeProject?.id == project.id }
    var isRunning: Bool { timerService.isRunning && isActiveProject }
    var elapsed: TimeInterval { timerService.elapsed }

    init(project: Project, sessionRepository: SessionRepositoryProtocol, timerService: TimerServiceProtocol) {
        self.project = project
        self.sessionRepository = sessionRepository
        self.timerService = timerService
        reload()
    }

    func reload() {
        do {
            sessions = try sessionRepository.fetchAll(for: project)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func start() {
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

    func stop() {
        do {
            try timerService.stop()
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteSession(_ session: Session) {
        do {
            try sessionRepository.delete(session)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
