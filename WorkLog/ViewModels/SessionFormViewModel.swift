import Foundation
import Observation

@MainActor
@Observable
final class SessionFormViewModel {
    var date: Date = .now
    var startTime: Date = .now
    var endTime: Date = .now
    var note: String = ""
    var errorMessage: String?

    private let project: Project
    private let sessionRepository: SessionRepositoryProtocol
    private let validationService: ValidationServiceProtocol
    private(set) var editingSession: Session?

    var isEditing: Bool { editingSession != nil }

    init(
        project: Project,
        sessionRepository: SessionRepositoryProtocol,
        validationService: ValidationServiceProtocol = ValidationService(),
        editing session: Session? = nil
    ) {
        self.project = project
        self.sessionRepository = sessionRepository
        self.validationService = validationService
        if let session {
            populate(from: session)
        }
    }

    func populate(from session: Session) {
        editingSession = session
        date = session.date
        startTime = session.startTime
        endTime = session.endTime ?? session.startTime
        note = session.note
    }

    @discardableResult
    func save() -> Bool {
        do {
            try validationService.validateSessionFields(project: project, startTime: startTime, endTime: endTime)

            let hasOverlap = try sessionRepository.hasOverlap(start: startTime, end: endTime, excluding: editingSession?.id)
            guard !hasOverlap else { throw ValidationError.overlappingSession }

            if let session = editingSession {
                session.date = date
                session.startTime = startTime
                session.endTime = endTime
                session.durationSeconds = endTime.timeIntervalSince(startTime)
                session.note = note
                try sessionRepository.update(session)
            } else {
                let session = Session(
                    project: project,
                    date: date,
                    startTime: startTime,
                    endTime: endTime,
                    durationSeconds: endTime.timeIntervalSince(startTime),
                    note: note,
                    category: project.category,
                    status: .completed
                )
                try sessionRepository.insert(session)
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
