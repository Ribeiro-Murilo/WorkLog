import Foundation
import SwiftData

@MainActor
protocol SessionRepositoryProtocol {
    func fetchAll(for project: Project?) throws -> [Session]
    func fetchSessions(in interval: DateInterval) throws -> [Session]
    func fetchActiveSession() throws -> Session?
    func fetchRecent(limit: Int) throws -> [Session]
    func hasOverlap(start: Date, end: Date, excluding id: UUID?) throws -> Bool
    func insert(_ session: Session) throws
    func update(_ session: Session) throws
    func delete(_ session: Session) throws
}

@MainActor
final class SessionRepository: SessionRepositoryProtocol {
    private let modelContext: ModelContext

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

    func hasOverlap(start: Date, end: Date, excluding id: UUID?) throws -> Bool {
        let distantFuture = Date.distantFuture
        let descriptor = FetchDescriptor<Session>(
            predicate: #Predicate { session in
                session.startTime < end && (session.endTime ?? distantFuture) > start
            }
        )
        let matches = try modelContext.fetch(descriptor)
        if let id {
            return matches.contains { $0.id != id }
        }
        return !matches.isEmpty
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
    }

    func update(_ session: Session) throws {
        session.updatedAt = .now
        try modelContext.save()
    }

    func delete(_ session: Session) throws {
        modelContext.delete(session)
        try modelContext.save()
    }
}
