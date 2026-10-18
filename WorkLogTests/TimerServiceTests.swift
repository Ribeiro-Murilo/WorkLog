import Testing
import Foundation
import Observation
import Synchronization
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

    @Test func globalResumeDoesNotRestartCompletedSession() throws {
        let sut = makeSUT()
        let project = Project(name: "Concluído", client: "C", dailyRate: 0, category: .work)
        try sut.projectRepository.insert(project)
        try sut.timerService.start(project: project)
        try sut.timerService.stop()

        try sut.timerService.resume()

        #expect(!sut.timerService.isRunning)
        #expect(try sut.sessionRepository.fetchAll(for: project).count == 1)
    }

    @Test func globalResumeDoesNotRestartManualSession() throws {
        let sut = makeSUT()
        let project = Project(name: "Manual", client: "C", dailyRate: 0, category: .work)
        try sut.projectRepository.insert(project)
        let end = Date.now.addingTimeInterval(-60)
        try sut.timerService.addManualSession(project: project, startTime: end.addingTimeInterval(-600), endTime: end, note: "")

        try sut.timerService.resume()

        #expect(!sut.timerService.isRunning)
        #expect(try sut.sessionRepository.fetchAll(for: project).count == 1)
    }

    @Test func globalResumePreservesRunningInterval() throws {
        let sut = makeSUT()
        let project = Project(name: "Rodando", client: "C", dailyRate: 0, category: .work)
        try sut.projectRepository.insert(project)
        try sut.timerService.start(project: project)
        let originalID = sut.timerService.activeSession?.id

        try sut.timerService.resume()

        #expect(sut.timerService.activeSession?.id == originalID)
        #expect(try sut.sessionRepository.fetchAll(for: project).count == 1)
        try sut.timerService.stop()
    }

    @Test func globalResumeDoesNotReviveOldPauseAfterLatestSessionWasCompleted() throws {
        let sut = makeSUT()
        let project = Project(name: "Histórico", client: "C", dailyRate: 0, category: .work)
        try sut.projectRepository.insert(project)
        try sut.timerService.start(project: project)
        try sut.timerService.pause()
        try sut.timerService.resume()
        try sut.timerService.stop()

        try sut.timerService.resume()

        #expect(!sut.timerService.isRunning)
        #expect(try sut.sessionRepository.fetchAll(for: project).count == 2)
    }

    @Test func globalResumeRejectsArchivedPausedProject() throws {
        let sut = makeSUT()
        let project = Project(name: "Arquivado", client: "C", dailyRate: 0, category: .work)
        try sut.projectRepository.insert(project)
        try sut.timerService.start(project: project)
        try sut.timerService.pause()
        try sut.projectRepository.archive(project, archived: true)

        try sut.timerService.resume()

        #expect(!sut.timerService.isRunning)
        #expect(try sut.sessionRepository.fetchAll(for: project).count == 1)
    }

    @Test func globalResumeConsultsPersistedRunningSession() throws {
        let sut = makeSUT()
        let project = Project(name: "Outra origem", client: "C", dailyRate: 0, category: .work)
        try sut.projectRepository.insert(project)
        let now = Date.now
        let running = Session(project: project, date: now, startTime: now, category: .work)
        try sut.sessionRepository.insert(running)

        try sut.timerService.resume()

        #expect(try sut.sessionRepository.fetchAll(for: project).count == 1)
        #expect(running.status == .running)
    }

    @Test func contextualResumeSelectsLatestPauseOfRequestedProjectAndAutoPausesCurrent() throws {
        let sut = makeSUT()
        let first = Project(name: "Primeiro", client: "C", dailyRate: 0, category: .work)
        let current = Project(name: "Atual", client: "C", dailyRate: 0, category: .work)
        try sut.projectRepository.insert(first)
        try sut.projectRepository.insert(current)
        try sut.timerService.start(project: first)
        try sut.timerService.pause()
        let original = try #require(sut.sessionRepository.fetchAll(for: first).first)
        let originalEnd = original.endTime
        try sut.timerService.start(project: current)
        let autoPaused = sut.timerService.activeSession
        #expect(try sut.timerService.resumableSession(for: first)?.id == original.id)
        #expect(try sut.timerService.resumableSession(for: nil) == nil)

        try sut.timerService.resume(project: first)
        let resumedID = sut.timerService.activeSession?.id
        try sut.timerService.resume(project: first)

        #expect(sut.timerService.activeProject?.id == first.id)
        #expect(sut.timerService.activeSession?.id == resumedID)
        #expect(resumedID != original.id)
        #expect(autoPaused?.status == .paused)
        #expect(original.endTime == originalEnd)
        #expect(try sut.sessionRepository.fetchAll(for: nil).filter { $0.status == .running }.count == 1)
        try sut.timerService.stop()
    }

    @Test func contextualResumeDoesNotReviveOldPauseAfterProjectCompleted() throws {
        let sut = makeSUT()
        let project = Project(name: "Encerrado", client: "C", dailyRate: 0, category: .work)
        try sut.projectRepository.insert(project)
        try sut.timerService.start(project: project)
        try sut.timerService.pause()
        try sut.timerService.resume()
        try sut.timerService.stop()

        #expect(try sut.timerService.resumableSession(for: project) == nil)
        try sut.timerService.resume(project: project)

        #expect(!sut.timerService.isRunning)
        #expect(try sut.sessionRepository.fetchAll(for: project).count == 2)
    }

    @Test func reopeningServiceResumesPausedProjectFromNowAndExcludesPauseDuration() throws {
        let sut = makeSUT()
        let project = Project(name: "Reabrir", client: "C", dailyRate: 0, category: .work)
        try sut.projectRepository.insert(project)
        let originalStart = Date.now.addingTimeInterval(-7200)
        let originalEnd = originalStart.addingTimeInterval(600)
        let original = Session(project: project, date: originalStart, startTime: originalStart,
                               endTime: originalEnd, durationSeconds: 600, category: .work, status: .paused)
        try sut.sessionRepository.insert(original)
        let reopened = TimerService(sessionRepository: sut.sessionRepository, projectRepository: sut.projectRepository,
                                    idleDetectionService: IdleDetectionService(idleThresholdMinutes: 10))
        let beforeResume = Date.now
        #expect(try reopened.resumableSession(for: nil)?.id == original.id)

        try reopened.resume()
        let resumed = try #require(reopened.activeSession)

        #expect(resumed.startTime >= beforeResume)
        #expect(resumed.id != original.id)
        #expect(resumed.durationSeconds == 0)
        #expect(original.durationSeconds == 600)
        #expect(original.endTime == originalEnd)
        try reopened.stop()
        #expect(try sut.sessionRepository.fetchAll(for: project).reduce(0) { $0 + $1.durationSeconds } < 610)
    }

    @Test func contextualResumeRevalidatesArchivedOrDeletedProject() throws {
        let sut = makeSUT()
        let project = Project(name: "Indisponível", client: "C", dailyRate: 0, category: .work)
        try sut.projectRepository.insert(project)
        try sut.timerService.start(project: project)
        try sut.timerService.pause()
        #expect(try sut.timerService.resumableSession(for: project) != nil)
        try sut.projectRepository.archive(project, archived: true)

        try sut.timerService.resume(project: project)
        #expect(!sut.timerService.isRunning)
        #expect(try sut.timerService.resumableSession(for: project) == nil)
        try sut.projectRepository.delete(project)
        try sut.timerService.resume(project: project)
        #expect(!sut.timerService.isRunning)
    }

    @Test func resumeEligibilityObservesSessionInsertionDeletionAndUpdate() throws {
        let context = makeInMemoryContext()
        let projects = ProjectRepository(modelContext: context)
        let sessions = SessionRepository(modelContext: context)
        let settings = SettingsRepository(modelContext: context)
        let project = Project(name: "Atualização observável", client: "C", dailyRate: 0, category: .work)
        try projects.insert(project)
        let start = Date.now.addingTimeInterval(-7200)
        let paused = Session(project: project, date: start, startTime: start,
                             endTime: start.addingTimeInterval(600), durationSeconds: 600,
                             category: .work, status: .paused)
        try sessions.insert(paused)
        let timer = TimerService(sessionRepository: sessions, projectRepository: projects,
                                 idleDetectionService: IdleDetectionService(idleThresholdMinutes: 10))
        let menu = TimerViewModel(timerService: timer, settingsRepository: settings)
        let detail = ProjectDetailViewModel(project: project, sessionRepository: sessions,
            commentRepository: CommentRepository(modelContext: context), timerService: timer)
        let insertNotified = Mutex(false)
        withObservationTracking {
            #expect(menu.canResume)
        } onChange: { insertNotified.withLock { $0 = true } }
        let contextualInsertNotified = Mutex(false)
        withObservationTracking {
            #expect(detail.canResume)
        } onChange: { contextualInsertNotified.withLock { $0 = true } }

        let manualStart = start.addingTimeInterval(1200)
        try timer.addManualSession(project: project, startTime: manualStart,
                                   endTime: manualStart.addingTimeInterval(600), note: "")

        #expect(insertNotified.withLock { $0 })
        #expect(contextualInsertNotified.withLock { $0 })
        #expect(!menu.canResume)
        #expect(!detail.canResume)
        let manual = try #require(sessions.fetchRecent(limit: 1).first)
        let deleteNotified = Mutex(false)
        withObservationTracking {
            #expect(!menu.canResume)
        } onChange: { deleteNotified.withLock { $0 = true } }
        let contextualDeleteNotified = Mutex(false)
        withObservationTracking {
            #expect(!detail.canResume)
        } onChange: { contextualDeleteNotified.withLock { $0 = true } }

        try sessions.delete(manual)

        #expect(deleteNotified.withLock { $0 })
        #expect(contextualDeleteNotified.withLock { $0 })
        #expect(menu.canResume)
        #expect(detail.canResume)
        let updateNotified = Mutex(false)
        withObservationTracking {
            #expect(menu.canResume)
        } onChange: { updateNotified.withLock { $0 = true } }
        let contextualUpdateNotified = Mutex(false)
        withObservationTracking {
            #expect(detail.canResume)
        } onChange: { contextualUpdateNotified.withLock { $0 = true } }

        paused.status = .completed
        try sessions.update(paused)

        #expect(updateNotified.withLock { $0 })
        #expect(contextualUpdateNotified.withLock { $0 })
        #expect(!menu.canResume)
        #expect(!detail.canResume)
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
