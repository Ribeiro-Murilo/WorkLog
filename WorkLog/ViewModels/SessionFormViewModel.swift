import Foundation
import Observation

@MainActor
@Observable
final class SessionFormViewModel {
    var date: Date = .now {
        didSet { moveToSelectedDay() }
    }
    var startTime: Date = .now {
        didSet {
            guard !synchronizingDates else { return }
            synchronizingDates = true
            date = calendar.startOfDay(for: startTime)
            synchronizingDates = false
            refreshAvailability()
        }
    }
    var endTime: Date = .now {
        didSet { if !synchronizingDates { refreshAvailability() } }
    }
    var note: String = ""
    var errorMessage: String?
    private(set) var conflictingSessions: [Session] = []
    private(set) var suggestedInterval: DateInterval?
    private(set) var availabilityError: String?

    private let project: Project
    private let sessionRepository: SessionRepositoryProtocol
    private let validationService: ValidationServiceProtocol
    private let calendar: Calendar
    @ObservationIgnored private var synchronizingDates = false
    private(set) var editingSession: Session?

    var isEditing: Bool { editingSession != nil }
    var isTimeEditingLocked: Bool { (editingSession?.workPeriods.count ?? 0) > 1 || editingSession?.status == .running }
    var timeEditingExplanation: String? {
        guard isTimeEditingLocked else { return nil }
        if editingSession?.status == .running { return "Pause ou encerre o timer antes de editar esta sessão." }
        return "Esta sessão possui vários trechos de trabalho. Os horários são preservados para manter as pausas; você pode editar a observação."
    }

    init(
        project: Project,
        sessionRepository: SessionRepositoryProtocol,
        validationService: ValidationServiceProtocol = ValidationService(),
        calendar: Calendar = .current,
        editing session: Session? = nil
    ) {
        self.project = project
        self.sessionRepository = sessionRepository
        self.validationService = validationService
        self.calendar = calendar
        if let session { populate(from: session) }
        else {
            date = calendar.startOfDay(for: startTime)
            refreshAvailability()
        }
    }

    func populate(from session: Session) {
        synchronizingDates = true
        editingSession = session
        startTime = session.startTime
        endTime = session.endTime ?? session.startTime
        date = calendar.startOfDay(for: startTime)
        note = session.note
        synchronizingDates = false
        refreshAvailability()
    }

    private func moveToSelectedDay() {
        guard !synchronizingDates else { return }
        let duration = endTime.timeIntervalSince(startTime)
        let time = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: startTime)
        var selected = calendar.dateComponents([.year, .month, .day], from: date)
        selected.hour = time.hour
        selected.minute = time.minute
        selected.second = time.second
        selected.nanosecond = time.nanosecond
        guard let newStart = calendar.date(from: selected) else { return }
        synchronizingDates = true
        date = calendar.startOfDay(for: newStart)
        startTime = newStart
        endTime = newStart.addingTimeInterval(duration)
        synchronizingDates = false
        refreshAvailability()
    }

    func refreshAvailability() {
        conflictingSessions = []
        suggestedInterval = nil
        availabilityError = nil
        errorMessage = nil
        guard !isTimeEditingLocked, endTime > startTime else { return }
        do {
            conflictingSessions = try sessionRepository.conflictingSessions(
                start: startTime, end: endTime, excluding: editingSession?.id)
            guard !conflictingSessions.isEmpty else { return }
            let occupied = try sessionRepository.fetchAll(for: nil)
                .filter { $0.id != editingSession?.id }
                .flatMap(\.occupiedWorkIntervals)
            suggestedInterval = SessionAvailability.nearestInterval(
                start: startTime, end: endTime, occupied: occupied, calendar: calendar)
        } catch {
            availabilityError = "Não foi possível consultar os horários: \(error.localizedDescription)"
        }
    }

    func applySuggestedInterval() {
        guard let interval = suggestedInterval else { return }
        synchronizingDates = true
        startTime = interval.start
        endTime = interval.end
        date = calendar.startOfDay(for: interval.start)
        synchronizingDates = false
        refreshAvailability()
    }

    @discardableResult
    func save() -> Bool {
        do {
            if let session = editingSession {
                guard session.status != .running else {
                    errorMessage = "Pause ou encerre o timer antes de editar esta sessão."
                    return false
                }
                if session.workPeriods.count > 1 {
                    session.note = note
                    try sessionRepository.update(session)
                    return true
                }
            }
            try validationService.validateSessionFields(project: project, startTime: startTime, endTime: endTime)
            refreshAvailability()
            let hasOverlap = try sessionRepository.hasOverlap(start: startTime, end: endTime, excluding: editingSession?.id)
            guard !hasOverlap else { throw ValidationError.overlappingSession }

            if let session = editingSession {
                session.date = calendar.startOfDay(for: startTime)
                session.startTime = startTime
                session.endTime = endTime
                session.durationSeconds = endTime.timeIntervalSince(startTime)
                if session.workPeriodsData != nil {
                    session.workPeriods = [.init(start: startTime, end: endTime)]
                }
                session.note = note
                try sessionRepository.update(session)
            } else {
                let session = Session(
                    project: project,
                    date: calendar.startOfDay(for: startTime),
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
