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
        return try modelContext.fetch(descriptor)
    }

    func fetchSessions(in interval: DateInterval) throws -> [Session] {
        let start = interval.start
        let end = interval.end
        let descriptor = FetchDescriptor<Session>(
            predicate: #Predicate { $0.startTime >= start && $0.startTime <= end },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
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
        let distantFuture = Date.distantFuture
        let descriptor = FetchDescriptor<Session>(
            predicate: #Predicate { session in
                session.startTime < end && (session.endTime ?? distantFuture) > start
            }
        )
        return try modelContext.fetch(descriptor)
            .filter { $0.id != id }
            .sorted { $0.startTime < $1.startTime }
    }

    func hasOverlap(start: Date, end: Date, excluding id: UUID?) throws -> Bool {
        try !conflictingSessions(start: start, end: end, excluding: id).isEmpty
    }

    func fetchRecent(limit: Int) throws -> [Session] {
        var descriptor = FetchDescriptor<Session>(
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor)
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
