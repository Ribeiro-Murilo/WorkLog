import Foundation
import Observation

@MainActor
@Observable
final class ProjectDetailViewModel {
    let project: Project

    private let sessionRepository: SessionRepositoryProtocol
    private let commentRepository: CommentRepositoryProtocol
    private let timerService: TimerServiceProtocol

    private(set) var sessions: [Session] = []
    private(set) var comments: [Comment] = []
    var errorMessage: String?

    var isActiveProject: Bool { timerService.activeProject?.id == project.id }
    var isRunning: Bool { timerService.isRunning && isActiveProject }
    var elapsed: TimeInterval { timerService.elapsed }

    init(project: Project, sessionRepository: SessionRepositoryProtocol, commentRepository: CommentRepositoryProtocol, timerService: TimerServiceProtocol) {
        self.project = project
        self.sessionRepository = sessionRepository
        self.commentRepository = commentRepository
        self.timerService = timerService
        reload()
    }

    func reload() {
        do {
            sessions = try sessionRepository.fetchAll(for: project)
            comments = try commentRepository.fetchAll(for: project)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addComment(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let comment = Comment(text: trimmed, author: NSFullUserName(), project: project)
            try commentRepository.insert(comment)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteComment(_ comment: Comment) {
        do {
            try commentRepository.delete(comment)
            reload()
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
