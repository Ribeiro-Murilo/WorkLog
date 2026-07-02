import Testing
import Foundation
@testable import WorkLog

@MainActor
struct ProjectRepositoryTests {
    @Test func insertAndFetch() throws {
        let repo = ProjectRepository(modelContext: makeInMemoryContext())
        let project = Project(name: "Site", client: "Acme", dailyRate: 500, category: .work)
        try repo.insert(project)

        let all = try repo.fetchAll(includeArchived: true)
        #expect(all.count == 1)
        #expect(all.first?.name == "Site")
    }

    @Test func duplicateDetection() throws {
        let repo = ProjectRepository(modelContext: makeInMemoryContext())
        let project = Project(name: "Site", client: "Acme", dailyRate: 500, category: .work)
        try repo.insert(project)

        #expect(try repo.isDuplicate(name: "Site", client: "Acme", excluding: nil))
        #expect(try !repo.isDuplicate(name: "Site", client: "Acme", excluding: project.id))
        #expect(try !repo.isDuplicate(name: "Other", client: "Acme", excluding: nil))
    }

    @Test func archiveExcludesFromDefaultFetch() throws {
        let repo = ProjectRepository(modelContext: makeInMemoryContext())
        let project = Project(name: "Site", client: "Acme", dailyRate: 500, category: .work)
        try repo.insert(project)

        try repo.archive(project, archived: true)

        #expect(try repo.fetchAll(includeArchived: false).isEmpty)
        #expect(try repo.fetchAll(includeArchived: true).count == 1)
    }

    @Test func deleteRemovesProject() throws {
        let repo = ProjectRepository(modelContext: makeInMemoryContext())
        let project = Project(name: "Site", client: "Acme", dailyRate: 500, category: .work)
        try repo.insert(project)

        try repo.delete(project)

        #expect(try repo.fetchAll(includeArchived: true).isEmpty)
    }

    @Test func searchFiltersByNameClientAndDescription() throws {
        let repo = ProjectRepository(modelContext: makeInMemoryContext())
        try repo.insert(Project(name: "Website Redesign", client: "Acme", dailyRate: 0, category: .work))
        try repo.insert(Project(name: "Mobile App", client: "Beta Corp", dailyRate: 0, category: .work))

        let results = try repo.search(query: "Acme", includeArchived: true)
        #expect(results.count == 1)
        #expect(results.first?.name == "Website Redesign")
    }
}
