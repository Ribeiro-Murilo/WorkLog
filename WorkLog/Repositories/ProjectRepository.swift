import Foundation
import SwiftData

@MainActor
protocol ProjectRepositoryProtocol {
    func fetchAll(includeArchived: Bool) throws -> [Project]
    func fetch(by id: UUID) throws -> Project?
    func search(query: String, includeArchived: Bool) throws -> [Project]
    func isDuplicate(name: String, client: String, excluding id: UUID?) throws -> Bool
    func insert(_ project: Project) throws
    func update(_ project: Project) throws
    func delete(_ project: Project) throws
    func archive(_ project: Project, archived: Bool) throws
}

@MainActor
final class ProjectRepository: ProjectRepositoryProtocol {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll(includeArchived: Bool) throws -> [Project] {
        let predicate: Predicate<Project> = includeArchived
            ? #Predicate { _ in true }
            : #Predicate { $0.isArchived == false }
        let descriptor = FetchDescriptor<Project>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.name)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetch(by id: UUID) throws -> Project? {
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(descriptor).first
    }

    func search(query: String, includeArchived: Bool) throws -> [Project] {
        guard !query.isEmpty else { return try fetchAll(includeArchived: includeArchived) }
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { project in
                (includeArchived || project.isArchived == false) &&
                (project.name.localizedStandardContains(query) ||
                 project.client.localizedStandardContains(query) ||
                 project.descriptionText.localizedStandardContains(query))
            },
            sortBy: [SortDescriptor(\.name)]
        )
        return try modelContext.fetch(descriptor)
    }

    func isDuplicate(name: String, client: String, excluding id: UUID?) throws -> Bool {
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { project in
                project.name == name && project.client == client
            }
        )
        let matches = try modelContext.fetch(descriptor)
        if let id {
            return matches.contains { $0.id != id }
        }
        return !matches.isEmpty
    }

    func insert(_ project: Project) throws {
        modelContext.insert(project)
        try modelContext.save()
    }

    func update(_ project: Project) throws {
        project.updatedAt = .now
        try modelContext.save()
    }

    func delete(_ project: Project) throws {
        modelContext.delete(project)
        try modelContext.save()
    }

    func archive(_ project: Project, archived: Bool) throws {
        project.isArchived = archived
        project.updatedAt = .now
        try modelContext.save()
    }
}
