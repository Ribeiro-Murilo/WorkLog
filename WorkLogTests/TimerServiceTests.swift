import Testing
import Foundation
@testable import WorkLog

@MainActor
struct TimerServiceTests {
    private func makeSUT() -> (timerService: TimerService, projectRepository: ProjectRepositoryProtocol, sessionRepository: SessionRepositoryProtocol) {
        let context = makeInMemoryContext()
        let projectRepository = ProjectRepository(modelContext: context)
        let sessionRepository = SessionRepository(modelContext: context)
        let idleDetectionService = IdleDetectionService(idleThresholdMinutes: 10)
        let timerService = TimerService(
            sessionRepository: sessionRepository,
            projectRepository: projectRepository,
            idleDetectionService: idleDetectionService
        )
        return (timerService, projectRepository, sessionRepository)
    }

    @Test func startingTimerCreatesRunningSession() throws {
        let sut = makeSUT()
        let project = Project(name: "P", client: "C", dailyRate: 0, category: .work)
        try sut.projectRepository.insert(project)

        try sut.timerService.start(project: project)

        #expect(sut.timerService.isRunning)
        #expect(sut.timerService.activeProject?.id == project.id)
        #expect(try sut.sessionRepository.fetchActiveSession()?.status == .running)
    }

    @Test func startingAnotherProjectAutoPausesPrevious() throws {
        let sut = makeSUT()
        let projectA = Project(name: "A", client: "C", dailyRate: 0, category: .work)
        let projectB = Project(name: "B", client: "C", dailyRate: 0, category: .work)
        try sut.projectRepository.insert(projectA)
        try sut.projectRepository.insert(projectB)

        try sut.timerService.start(project: projectA)
        let sessionA = sut.timerService.activeSession

        try sut.timerService.start(project: projectB)

        #expect(sut.timerService.activeProject?.id == projectB.id)
        #expect(sessionA?.status == .paused)

        let allSessions = try sut.sessionRepository.fetchAll(for: nil)
        #expect(allSessions.count == 2)
    }

    @Test func onlyOneRunningSessionExistsAtATime() throws {
        let sut = makeSUT()
        let projectA = Project(name: "A", client: "C", dailyRate: 0, category: .work)
        let projectB = Project(name: "B", client: "C", dailyRate: 0, category: .work)
        try sut.projectRepository.insert(projectA)
        try sut.projectRepository.insert(projectB)

        try sut.timerService.start(project: projectA)
        try sut.timerService.start(project: projectB)

        let allSessions = try sut.sessionRepository.fetchAll(for: nil)
        let runningCount = allSessions.filter { $0.status == .running }.count
        #expect(runningCount == 1)
    }

    @Test func pauseClearsActiveSession() throws {
        let sut = makeSUT()
        let project = Project(name: "P", client: "C", dailyRate: 0, category: .work)
        try sut.projectRepository.insert(project)
        try sut.timerService.start(project: project)

        try sut.timerService.pause()

        #expect(!sut.timerService.isRunning)
        #expect(sut.timerService.activeSession == nil)
        #expect(try sut.sessionRepository.fetchActiveSession() == nil)
    }

    @Test func stopMarksSessionCompleted() throws {
        let sut = makeSUT()
        let project = Project(name: "P", client: "C", dailyRate: 0, category: .work)
        try sut.projectRepository.insert(project)
        try sut.timerService.start(project: project)

        try sut.timerService.stop()

        let sessions = try sut.sessionRepository.fetchAll(for: project)
        #expect(sessions.first?.status == .completed)
    }

    @Test func manualSessionRejectsInvalidRange() throws {
        let sut = makeSUT()
        let project = Project(name: "P", client: "C", dailyRate: 0, category: .work)
        try sut.projectRepository.insert(project)

        let start = Date()
        let end = start.addingTimeInterval(-100)

        #expect(throws: ValidationError.self) {
            try sut.timerService.addManualSession(project: project, startTime: start, endTime: end, note: "")
        }
    }

    @Test func manualSessionRejectsOverlap() throws {
        let sut = makeSUT()
        let project = Project(name: "P", client: "C", dailyRate: 0, category: .work)
        try sut.projectRepository.insert(project)

        let start = Date()
        let end = start.addingTimeInterval(3600)
        try sut.timerService.addManualSession(project: project, startTime: start, endTime: end, note: "")

        #expect(throws: ValidationError.self) {
            try sut.timerService.addManualSession(
                project: project,
                startTime: start.addingTimeInterval(1800),
                endTime: end.addingTimeInterval(1800),
                note: ""
            )
        }
    }
}
