import Foundation
import SwiftData

@MainActor
protocol CommentRepositoryProtocol {
    func fetchAll(for project: Project) throws -> [Comment]
    func insert(_ comment: Comment) throws
    func delete(_ comment: Comment) throws
}

@MainActor
final class CommentRepository: CommentRepositoryProtocol {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll(for project: Project) throws -> [Comment] {
        let projectId = project.id
        let descriptor = FetchDescriptor<Comment>(
            predicate: #Predicate { $0.project?.id == projectId },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func insert(_ comment: Comment) throws {
        modelContext.insert(comment)
        try modelContext.save()
    }

    func delete(_ comment: Comment) throws {
        modelContext.delete(comment)
        try modelContext.save()
    }
}
