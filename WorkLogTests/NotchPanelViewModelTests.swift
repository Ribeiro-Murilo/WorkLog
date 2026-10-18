import Foundation
import Testing
@testable import WorkLog

@MainActor
struct NotchPanelViewModelTests {
    private struct Fixture {
        let projects: ProjectRepository
        let sessions: SessionRepository
        let settings: SettingsRepository
        let timer: TimerService
        let model: NotchPanelViewModel
    }

    private func makeFixture() -> Fixture {
        let context = makeInMemoryContext()
        let projects = ProjectRepository(modelContext: context)
        let sessions = SessionRepository(modelContext: context)
        let settings = SettingsRepository(modelContext: context)
        let timer = TimerService(
            sessionRepository: sessions,
            projectRepository: projects,
            idleDetectionService: IdleDetectionService(idleThresholdMinutes: 10)
        )
        return Fixture(projects: projects, sessions: sessions, settings: settings, timer: timer,
                       model: NotchPanelViewModel(timerService: timer, projectRepository: projects,
                                                 sessionRepository: sessions, settingsRepository: settings))
    }

    private func project(_ name: String, client: String = "Cliente", favorite: Bool = false) -> Project {
        Project(name: name, client: client, dailyRate: 0, category: .work, isFavorite: favorite)
    }

    private func session(_ project: Project, status: SessionStatus, duration: TimeInterval = 60) -> Session {
        let start = Date.now.addingTimeInterval(-duration - 1)
        return Session(project: project, date: start, startTime: start,
                       endTime: status == .running ? nil : start.addingTimeInterval(duration),
                       durationSeconds: duration, category: .work, status: status)
    }

    @Test func searchFindsAllProjectsByNameAndClientIgnoringAccents() throws {
        let sut = makeFixture()
        let favorite = project("Favorito", favorite: true)
        let other = project("Gestão", client: "Órbita")
        try sut.projects.insert(favorite)
        try sut.projects.insert(other)
        sut.model.reload()
        #expect(sut.model.visibleProjects.map(\.id) == [favorite.id])

        sut.model.query = "gestao"
        #expect(sut.model.visibleProjects.map(\.id) == [other.id])
        sut.model.query = " orbita "
        #expect(sut.model.visibleProjects.map(\.id) == [other.id])
        sut.model.query = "não existe"
        #expect(sut.model.visibleProjects.isEmpty)
    }

    @Test func favoritesAndRecentProjectsAreDeduplicatedAndExcludeArchivedAndActive() throws {
        let sut = makeFixture()
        let favorite = project("Favorito", favorite: true)
        let recent = project("Recente")
        let archived = project("Arquivado", favorite: true)
        archived.isArchived = true
        for project in [favorite, recent, archived] { try sut.projects.insert(project) }
        try sut.sessions.insert(session(favorite, status: .completed, duration: 180))
        try sut.sessions.insert(session(recent, status: .completed, duration: 120))
        try sut.sessions.insert(session(recent, status: .completed, duration: 100))
        try sut.sessions.insert(session(archived, status: .completed, duration: 90))
        sut.model.reload()
        #expect(sut.model.visibleProjects.map(\.id) == [favorite.id, recent.id])

        sut.model.start(project: favorite)
        #expect(sut.model.visibleProjects.map(\.id) == [recent.id])
        sut.model.query = "Arquivado"
        #expect(sut.model.visibleProjects.isEmpty)
        sut.model.stop()
    }

    @Test func noFavoritesOrRecentSessionsFallsBackToAvailableProjects() throws {
        let sut = makeFixture()
        let available = project("Primeiro projeto")
        try sut.projects.insert(available)
        sut.model.reload()
        #expect(sut.model.state == .idle)
        #expect(sut.model.project == nil)
        #expect(sut.model.visibleProjects.map(\.id) == [available.id])
    }

    @Test func pauseResumeAndStopUseSameSession() throws {
        let sut = makeFixture()
        let project = project("WorkLog")
        try sut.projects.insert(project)
        sut.model.start(project: project)
        let originalID = sut.timer.activeSession?.id
        #expect(sut.model.state == .running)
        sut.model.pause()
        #expect(sut.model.state == .paused)
        #expect(sut.model.project?.id == project.id)
        #expect(sut.model.elapsed == (try sut.sessions.fetchRecent(limit: 1).first?.durationSeconds))

        sut.model.resume()
        #expect(sut.model.state == .running)
        #expect(sut.timer.activeSession?.id == originalID)
        #expect(try sut.sessions.fetchAll(for: nil).count == 1)
        let running = try sut.sessions.fetchAll(for: nil).filter { $0.status == .running }
        #expect(running.count == 1)
        sut.model.stop()
        #expect(sut.model.state == .idle)
        #expect(sut.model.project == nil)
        #expect(try sut.sessions.fetchRecent(limit: 1).first?.status == .completed)
    }

    @Test func externalPauseCanBeReloadedAndDailyTotalIncludesOnlyClosedSessions() throws {
        let sut = makeFixture()
        let project = project("WorkLog")
        try sut.projects.insert(project)
        try sut.sessions.insert(session(project, status: .completed, duration: 3600))
        try sut.sessions.insert(session(project, status: .paused, duration: 1200))
        let openSession = session(project, status: .running, duration: 500)
        try sut.sessions.insert(openSession)
        sut.model.reload()
        #expect(sut.model.todayTotal == 4800)
        try sut.sessions.delete(openSession)

        // Use the service externally, like idle detection, then refresh the panel.
        sut.model.start(project: project)
        try sut.timer.pause()
        sut.model.reload()
        #expect(sut.model.state == .paused)
        #expect(sut.model.project?.id == project.id)
    }

    @Test func actionErrorsAreVisibleAndSuccessfulReloadClearsThem() {
        let sut = makeFixture()
        let timer = FailingNotchTimer()
        let model = NotchPanelViewModel(timerService: timer, projectRepository: sut.projects,
                                        sessionRepository: sut.sessions, settingsRepository: sut.settings)
        model.start(project: project("WorkLog"))
        #expect(model.errorMessage == "Falha ao salvar a sessão.")
        #expect(model.state == .idle)
        model.reload()
        #expect(model.errorMessage == nil)
    }

    @Test func archivingPausedProjectImmediatelyRemovesResumeAndCannotRestartIt() throws {
        let sut = makeFixture()
        let project = project("Arquivar após pausa")
        try sut.projects.insert(project)
        sut.model.start(project: project)
        sut.model.pause()
        #expect(sut.model.state == .paused)

        try sut.projects.archive(project, archived: true)
        #expect(sut.model.state == .idle)
        #expect(sut.model.project == nil)
        sut.model.resume()
        #expect(!sut.timer.isRunning)
    }

    @Test func resumeRechecksLatestSessionBeforeStartingAnotherInterval() throws {
        let sut = makeFixture()
        let project = project("Pausado")
        let other = self.project("Registro mais recente")
        try sut.projects.insert(project)
        try sut.projects.insert(other)
        sut.model.start(project: project)
        sut.model.pause()
        try sut.sessions.insert(Session(project: other, date: .now, startTime: .now,
            endTime: .now, durationSeconds: 60, category: .work, status: .completed))
        sut.model.resume()
        #expect(!sut.timer.isRunning)
        #expect(sut.model.state == .idle)
    }

    @Test func resumeRefreshesAnotherSessionOfSameProjectBeforeResumingIt() throws {
        let sut = makeFixture()
        let project = project("Projeto")
        try sut.projects.insert(project)
        sut.model.start(project: project)
        sut.model.pause()
        let originalID = try #require(sut.timer.resumableSession(for: nil)?.id)
        let newSession = Session(project: project, date: .now, startTime: .now,
            endTime: .now, durationSeconds: 60, category: .work, status: .paused)
        try sut.sessions.insert(newSession)
        sut.model.resume()
        #expect(!sut.timer.isRunning)
        #expect(try sut.timer.resumableSession(for: nil)?.id == newSession.id)
        #expect(newSession.id != originalID)
        sut.model.resume()
        #expect(sut.timer.activeSession?.id == newSession.id)
        sut.model.stop()
    }

    @Test func secondsPreferenceUpdatesWithoutReopeningPinnedPanel() throws {
        let sut = makeFixture()
        let settings = try sut.settings.current()
        settings.showSeconds = true
        sut.model.reload()
        #expect(sut.model.elapsedFormatted == "00:00:00")
        settings.showSeconds = false
        #expect(sut.model.elapsedFormatted == "00:00")
    }

    @Test func resumeRefreshesDifferentPausedProjectWithoutStartingItOnTheFirstClick() throws {
        let sut = makeFixture()
        let original = project("Projeto mostrado")
        let other = project("Outra sessão pausada")
        try sut.projects.insert(original)
        try sut.projects.insert(other)
        sut.model.start(project: original)
        sut.model.pause()
        try sut.sessions.insert(Session(project: other, date: .now, startTime: .now,
            endTime: .now, durationSeconds: 60, category: .work, status: .paused))
        sut.model.resume()
        #expect(!sut.timer.isRunning)
        #expect(sut.model.project?.id == other.id)
        sut.model.resume()
        #expect(sut.timer.activeProject?.id == other.id)
        sut.model.stop()
    }
}

@MainActor
private final class FailingNotchTimer: TimerServiceProtocol {
    var activeSession: Session? { nil }
    var activeProject: Project? { nil }
    var elapsed: TimeInterval { 0 }
    var isRunning: Bool { false }
    struct Failure: LocalizedError {
        var errorDescription: String? { "Falha ao salvar a sessão." }
    }
    func start(project: Project) throws { throw Failure() }
    func pause() throws { throw Failure() }
    func resumableSession(for project: Project?) throws -> Session? { nil }
    func resume(project: Project) throws { throw Failure() }
    func resume() throws { throw Failure() }
    func stop() throws { throw Failure() }
    func addManualSession(project: Project, startTime: Date, endTime: Date, note: String) throws { throw Failure() }
}
