import Foundation
import Observation
import SwiftData

@MainActor
protocol SessionRepositoryProtocol {
    var dataRevision: Int { get }
    func fetchAll(for project: Project?) throws -> [Session]
    func fetchSessions(in interval: DateInterval) throws -> [Session]
    func fetchActiveSession() throws -> Session?
    func fetchRecent(limit: Int) throws -> [Session]
    func conflictingSessions(start: Date, end: Date, excluding id: UUID?) throws -> [Session]
    func hasOverlap(start: Date, end: Date, excluding id: UUID?) throws -> Bool
    func insert(_ session: Session) throws
    func update(_ session: Session) throws
    func delete(_ session: Session) throws
}

@MainActor
@Observable
final class SessionRepository: SessionRepositoryProtocol {
    private let modelContext: ModelContext
    private(set) var dataRevision = 0

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll(for project: Project?) throws -> [Session] {
        let descriptor: FetchDescriptor<Session>
        if let project {
            let projectId = project.id
            descriptor = FetchDescriptor<Session>(
                predicate: #Predicate { $0.project?.id == projectId },
                sortBy: [SortDescriptor(\.startTime, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor<Session>(
                sortBy: [SortDescriptor(\.startTime, order: .reverse)]
            )
        }
        return try modelContext.fetch(descriptor).sorted { $0.latestActivity > $1.latestActivity }
    }

    func fetchSessions(in interval: DateInterval) throws -> [Session] {
        try fetchAll(for: nil).filter { session in
            session.occupiedWorkIntervals.contains { $0.start < interval.end && $0.end > interval.start }
        }
    }

    func fetchActiveSession() throws -> Session? {
        // Comparar um enum diretamente em #Predicate provoca uma falha em tempo de execução
        // no SwiftData desta toolchain; filtramos em memória para contornar o problema.
        let descriptor = FetchDescriptor<Session>(sortBy: [SortDescriptor(\.startTime, order: .reverse)])
        let sessions = try modelContext.fetch(descriptor)
        return sessions.first { $0.status == .running }
    }

    func conflictingSessions(start: Date, end: Date, excluding id: UUID?) throws -> [Session] {
        guard end > start else { return [] }
        return try fetchAll(for: nil)
            .filter { session in
                session.id != id && session.occupiedWorkIntervals.contains { $0.start < end && $0.end > start }
            }
            .sorted { $0.latestActivity < $1.latestActivity }
    }

    func hasOverlap(start: Date, end: Date, excluding id: UUID?) throws -> Bool {
        try !conflictingSessions(start: start, end: end, excluding: id).isEmpty
    }

    func fetchRecent(limit: Int) throws -> [Session] {
        Array(try fetchAll(for: nil).prefix(max(0, limit)))
    }

    func insert(_ session: Session) throws {
        modelContext.insert(session)
        try modelContext.save()
        dataRevision += 1
    }

    func update(_ session: Session) throws {
        session.updatedAt = .now
        try modelContext.save()
        dataRevision += 1
    }

    func delete(_ session: Session) throws {
        modelContext.delete(session)
        try modelContext.save()
        dataRevision += 1
    }
}


/// Finds the closest free interval in the calendar day containing the requested start.
/// Busy intervals are clipped to the day, including sessions that started before midnight.
struct SessionAvailability {
    static func nearestInterval(
        start: Date, end: Date, occupied: [DateInterval], calendar: Calendar = .current
    ) -> DateInterval? {
        let duration = end.timeIntervalSince(start)
        guard duration > 0, duration.isFinite,
              let day = calendar.dateInterval(of: .day, for: start),
              duration <= day.duration else { return nil }

        let busy = occupied.compactMap { interval -> DateInterval? in
            let clippedStart = max(interval.start, day.start)
            let clippedEnd = min(interval.end, day.end)
            guard clippedEnd > clippedStart else { return nil }
            return DateInterval(start: clippedStart, end: clippedEnd)
        }.sorted { $0.start < $1.start }

        var cursor = day.start
        var gaps: [DateInterval] = []
        for interval in busy {
            if interval.start > cursor {
                gaps.append(DateInterval(start: cursor, end: interval.start))
            }
            cursor = max(cursor, interval.end)
        }
        if cursor < day.end { gaps.append(DateInterval(start: cursor, end: day.end)) }

        let candidates = gaps.filter { $0.duration >= duration }.map { gap in
            let latestStart = gap.end.addingTimeInterval(-duration)
            let candidateStart = min(max(start, gap.start), latestStart)
            return DateInterval(start: candidateStart, duration: duration)
        }
        return candidates.min { lhs, rhs in
            let leftDistance = abs(lhs.start.timeIntervalSince(start))
            let rightDistance = abs(rhs.start.timeIntervalSince(start))
            return leftDistance == rightDistance ? lhs.start > rhs.start : leftDistance < rightDistance
        }
    }
}


/// Trecho de trabalho fechado, recortado pelo período e pelo dia, sem criar outro registro.
struct SessionRecordedSlice {
    let start: Date
    let end: Date
    let duration: TimeInterval
}

extension Session {
    /// Um trecho aberto reserva o futuro; o intervalo entre trechos continua disponível.
    var occupiedWorkIntervals: [DateInterval] {
        if workPeriodsData == nil {
            let end = endTime ?? .distantFuture
            return end > startTime ? [DateInterval(start: startTime, end: end)] : []
        }
        return workPeriods.compactMap { period in
            let end = period.end ?? .distantFuture
            return end > period.start ? DateInterval(start: period.start, end: end) : nil
        }
    }

    /// Totais persistidos contam apenas trechos fechados, inclusive de uma sessão retomada em execução.
    func recordedSlices(in interval: DateInterval, calendar: Calendar = .current) -> [SessionRecordedSlice] {
        let periods: [SessionWorkPeriod]
        let scale: Double
        if workPeriodsData == nil {
            guard status != .running, let endTime, endTime > startTime else { return [] }
            periods = [.init(start: startTime, end: endTime)]
            // Registros legados podem ter duração ajustada: preservar seu total armazenado.
            scale = max(0, durationSeconds) / endTime.timeIntervalSince(startTime)
        } else {
            periods = workPeriods
            scale = 1
        }
        return periods.flatMap { period -> [SessionRecordedSlice] in
            guard let end = period.end else { return [] }
            var cursor = max(period.start, interval.start)
            let limit = min(end, interval.end)
            var slices: [SessionRecordedSlice] = []
            while cursor < limit {
                let dayEnd = calendar.dateInterval(of: .day, for: cursor)?.end ?? limit
                let sliceEnd = min(limit, dayEnd)
                guard sliceEnd > cursor else { break }
                let duration = sliceEnd.timeIntervalSince(cursor) * scale
                if duration > 0 { slices.append(.init(start: cursor, end: sliceEnd, duration: duration)) }
                cursor = sliceEnd
            }
            return slices
        }
    }

    func recordedDuration(in interval: DateInterval = DateInterval(start: .distantPast, end: .distantFuture)) -> TimeInterval {
        recordedSlices(in: interval).reduce(0) { $0 + $1.duration }
    }

    func recordedReportRows(in interval: DateInterval) -> [ReportRow] {
        recordedSlices(in: interval).enumerated().map { index, slice in
            let rate = project?.dailyRate ?? 0
            let value = rate > 0 ? rate * Decimal(slice.duration / 3600 / Project.standardWorkdayHours) : 0
            return ReportRow(id: "\(id.uuidString)#\(index)", projectName: project?.name ?? "—",
                client: project?.client ?? "—", date: Calendar.current.startOfDay(for: slice.start),
                startTime: slice.start, endTime: slice.end, durationSeconds: slice.duration,
                category: category, status: status, estimatedValue: value, note: note,
                tags: project?.tags ?? [], descriptionText: project?.descriptionText ?? "", sessionCount: 1)
        }
    }
}
