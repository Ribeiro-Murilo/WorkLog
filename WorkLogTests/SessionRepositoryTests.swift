import Testing
import Foundation
@testable import WorkLog

@MainActor
struct SessionRepositoryTests {
    @Test func overlapDetection() throws {
        let context = makeInMemoryContext()
        let projectRepo = ProjectRepository(modelContext: context)
        let sessionRepo = SessionRepository(modelContext: context)

        let project = Project(name: "P", client: "C", dailyRate: 0, category: .work)
        try projectRepo.insert(project)

        let start = Date()
        let end = start.addingTimeInterval(3600)
        let session = Session(project: project, date: start, startTime: start, endTime: end, durationSeconds: 3600, category: .work, status: .completed)
        try sessionRepo.insert(session)

        let overlapping = try sessionRepo.hasOverlap(start: start.addingTimeInterval(1800), end: end.addingTimeInterval(1800), excluding: nil)
        #expect(overlapping)

        let nonOverlapping = try sessionRepo.hasOverlap(start: end.addingTimeInterval(60), end: end.addingTimeInterval(120), excluding: nil)
        #expect(!nonOverlapping)

        let excludingItself = try sessionRepo.hasOverlap(start: start, end: end, excluding: session.id)
        #expect(!excludingItself)
    }

    @Test func fetchActiveSessionReturnsOnlyRunning() throws {
        let context = makeInMemoryContext()
        let projectRepo = ProjectRepository(modelContext: context)
        let sessionRepo = SessionRepository(modelContext: context)

        let project = Project(name: "P", client: "C", dailyRate: 0, category: .work)
        try projectRepo.insert(project)

        let pausedSession = Session(project: project, date: .now, startTime: .now, endTime: .now, category: .work, status: .paused)
        try sessionRepo.insert(pausedSession)

        #expect(try sessionRepo.fetchActiveSession() == nil)

        let runningSession = Session(project: project, date: .now, startTime: .now, category: .work, status: .running)
        try sessionRepo.insert(runningSession)

        #expect(try sessionRepo.fetchActiveSession()?.id == runningSession.id)
    }

    @Test func fetchRecentOrdersByStartTimeDescending() throws {
        let context = makeInMemoryContext()
        let projectRepo = ProjectRepository(modelContext: context)
        let sessionRepo = SessionRepository(modelContext: context)

        let project = Project(name: "P", client: "C", dailyRate: 0, category: .work)
        try projectRepo.insert(project)

        let older = Session(project: project, date: .now, startTime: Date().addingTimeInterval(-3600), endTime: Date(), category: .work, status: .completed)
        let newer = Session(project: project, date: .now, startTime: Date(), endTime: Date(), category: .work, status: .completed)
        try sessionRepo.insert(older)
        try sessionRepo.insert(newer)

        let recent = try sessionRepo.fetchRecent(limit: 1)
        #expect(recent.first?.id == newer.id)
    }
}
