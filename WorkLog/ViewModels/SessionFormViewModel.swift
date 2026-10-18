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
    private(set) var cyclePeriods: [SessionWorkPeriod] = []
    private(set) var cycleValidationMessage: String?
    private var sourcePeriods: [SessionWorkPeriod] = []
    private var sourceStatus: SessionStatus?

    private let project: Project
    private let sessionRepository: SessionRepositoryProtocol
    private let validationService: ValidationServiceProtocol
    private let calendar: Calendar
    @ObservationIgnored private var synchronizingDates = false
    private(set) var editingSession: Session?

    var isEditing: Bool { editingSession != nil }
    var usesCycleEditor: Bool { isEditing && sourcePeriods.count > 1 }
    var cyclesTotal: TimeInterval {
        cyclePeriods.reduce(0) { $0 + max(0, ($1.end ?? $1.start).timeIntervalSince($1.start)) }
    }
    var isTimeEditingLocked: Bool { editingSession?.status == .running }
    var timeEditingExplanation: String? {
        guard isTimeEditingLocked else { return nil }
        return "Pause ou encerre o timer antes de editar esta sessão."
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
        sourcePeriods = session.workPeriods
        sourceStatus = session.status
        cyclePeriods = sourcePeriods
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
        cycleValidationMessage = nil
        guard !isTimeEditingLocked else { return }
        if usesCycleEditor {
            do { cycleValidationMessage = try cycleProblem() }
            catch { availabilityError = "Não foi possível consultar os horários: \(error.localizedDescription)" }
            return
        }
        guard endTime > startTime else { return }
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
        guard !usesCycleEditor, !isTimeEditingLocked else { return }
        guard let interval = suggestedInterval else { return }
        synchronizingDates = true
        startTime = interval.start
        endTime = interval.end
        date = calendar.startOfDay(for: interval.start)
        synchronizingDates = false
        refreshAvailability()
    }

    func updateCycleStart(at index: Int, to date: Date) {
        guard usesCycleEditor, !isTimeEditingLocked, cyclePeriods.indices.contains(index) else { return }
        cyclePeriods[index].start = date
        refreshAvailability()
    }

    func updateCycleEnd(at index: Int, to date: Date) {
        guard usesCycleEditor, !isTimeEditingLocked, cyclePeriods.indices.contains(index) else { return }
        cyclePeriods[index].end = date
        refreshAvailability()
    }

    /// Valida os trechos, sem usar o envelope da sessão que também inclui as pausas.
    private func cycleProblem() throws -> String? {
        for (index, period) in cyclePeriods.enumerated() {
            guard let end = period.end, period.start.timeIntervalSinceReferenceDate.isFinite,
                  end.timeIntervalSinceReferenceDate.isFinite, end > period.start else {
                return "Ciclo \(index + 1): o fim deve ser posterior ao início."
            }
            try validationService.validateSessionFields(project: project, startTime: period.start, endTime: end)
            if index > 0, let previousEnd = cyclePeriods[index - 1].end, period.start < previousEnd {
                return "Ciclo \(index + 1): o início deve ser igual ou posterior ao fim do ciclo \(index)."
            }
        }
        for (index, period) in cyclePeriods.enumerated() {
            guard let end = period.end else { continue }
            let conflicts = try sessionRepository.conflictingSessions(
                start: period.start, end: end, excluding: editingSession?.id)
            if let conflict = conflicts.first {
                conflictingSessions = conflicts
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "pt_BR")
                formatter.calendar = calendar
                formatter.timeZone = calendar.timeZone
                formatter.dateFormat = "dd/MM/yyyy HH:mm:ss"
                let busy = conflict.occupiedWorkIntervals.first { $0.start < end && $0.end > period.start }
                let startText = formatter.string(from: busy?.start ?? conflict.startTime)
                let endText = busy?.end == .distantFuture ? "em andamento"
                    : formatter.string(from: busy?.end ?? conflict.endTime ?? conflict.startTime)
                return "Ciclo \(index + 1): conflito com \(conflict.project?.name ?? "outro projeto"), de \(startText) até \(endText)."
            }
        }
        return nil
    }

    /// A edição aberta não pode sobrescrever um ciclo criado por outra retomada.
    private func canSave(_ session: Session) throws -> Bool {
        guard let persisted = try sessionRepository.fetchAll(for: nil).first(where: { $0.id == session.id }) else {
            errorMessage = "Esta sessão foi removida. Feche o formulário e atualize a lista."
            return false
        }
        guard persisted.status != .running else {
            errorMessage = "Pause ou encerre o timer antes de editar esta sessão."
            return false
        }
        guard persisted.workPeriods == sourcePeriods, persisted.status == sourceStatus else {
            errorMessage = "Os ciclos desta sessão foram alterados. Reabra a edição para carregar os horários atuais."
            return false
        }
        return true
    }

    @discardableResult
    func save() -> Bool {
        do {
            if let session = editingSession {
                guard try canSave(session) else { return false }
                if usesCycleEditor {
                    refreshAvailability()
                    if let problem = cycleValidationMessage ?? availabilityError {
                        errorMessage = problem
                        return false
                    }
                    guard let first = cyclePeriods.first, let lastEnd = cyclePeriods.last?.end else { return false }
                    session.workPeriods = cyclePeriods
                    session.date = calendar.startOfDay(for: first.start)
                    session.startTime = first.start
                    session.endTime = lastEnd
                    session.durationSeconds = cyclesTotal
                    session.note = note
                    try sessionRepository.update(session)
                    sourcePeriods = session.workPeriods
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
