import Foundation
import Observation

enum ProjectSortOption: String, CaseIterable, Identifiable {
    case name
    case client
    case createdAt

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .name: return "Nome"
        case .client: return "Cliente"
        case .createdAt: return "Data de criação"
        }
    }
}

@MainActor
@Observable
final class ProjectListViewModel {
    private(set) var projects: [Project] = []
    var errorMessage: String?

    var searchQuery: String = "" {
        didSet { reload() }
    }
    var statusFilter: ProjectStatus? {
        didSet { reload() }
    }
    var categoryFilter: ProjectCategory? {
        didSet { reload() }
    }
    var includeArchived: Bool = false {
        didSet { reload() }
    }
    var sortOption: ProjectSortOption = .name {
        didSet { reload() }
    }

    private let repository: ProjectRepositoryProtocol

    init(repository: ProjectRepositoryProtocol) {
        self.repository = repository
        reload()
    }

    func reload() {
        do {
            var results = try repository.search(query: searchQuery, includeArchived: includeArchived)
            if let statusFilter {
                results = results.filter { $0.status == statusFilter }
            }
            if let categoryFilter {
                results = results.filter { $0.category == categoryFilter }
            }
            results.sort(by: comparator(for: sortOption))
            projects = results
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ project: Project) {
        do {
            try repository.delete(project)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleArchive(_ project: Project) {
        do {
            try repository.archive(project, archived: !project.isArchived)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleFavorite(_ project: Project) {
        do {
            project.isFavorite.toggle()
            try repository.update(project)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func comparator(for option: ProjectSortOption) -> (Project, Project) -> Bool {
        switch option {
        case .name:
            return { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .client:
            return { $0.client.localizedStandardCompare($1.client) == .orderedAscending }
        case .createdAt:
            return { $0.createdAt > $1.createdAt }
        }
    }
}
