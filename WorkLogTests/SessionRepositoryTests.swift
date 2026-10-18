import Testing
import AppKit
import SwiftUI
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


@MainActor
struct SessionAvailabilityTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func time(_ hour: Int, _ minute: Int = 0, day: Int = 17) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test func conflictsIncludeOtherProjectsMidnightAndRunningButExcludeSelfAndAdjacent() throws {
        let context = makeInMemoryContext()
        let repository = SessionRepository(modelContext: context)
        let ownProject = Project(name: "Meu projeto", client: "C", dailyRate: 0, category: .work)
        let otherProject = Project(name: "Outro projeto", client: "C", dailyRate: 0, category: .work)
        let own = Session(project: ownProject, date: time(0), startTime: time(0), endTime: time(2), category: .work, status: .completed)
        let crossing = Session(project: otherProject, date: time(23, day: 16), startTime: time(23, day: 16), endTime: time(1), category: .work, status: .completed)
        let adjacent = Session(project: otherProject, date: time(2), startTime: time(2), endTime: time(3), category: .work, status: .completed)
        try repository.insert(own)
        try repository.insert(crossing)
        try repository.insert(adjacent)
        let conflicts = try repository.conflictingSessions(start: time(0), end: time(2), excluding: own.id)
        #expect(conflicts.map(\.id) == [crossing.id])
        #expect(conflicts.first?.project?.name == "Outro projeto")
        #expect(try repository.hasOverlap(start: time(3), end: time(4), excluding: nil) == false)
        let running = Session(project: otherProject, date: time(9), startTime: time(9), category: .work, status: .running)
        try repository.insert(running)
        #expect(try repository.conflictingSessions(start: time(20), end: time(21), excluding: nil).map(\.id) == [running.id])
    }

    @Test func suggestionUsesClosestGapAndPrefersLaterOnTie() {
        let suggestion = SessionAvailability.nearestInterval(start: time(10), end: time(11), occupied: [DateInterval(start: time(10), end: time(11))], calendar: calendar)
        #expect(suggestion == DateInterval(start: time(11), end: time(12)))
        let closerBefore = SessionAvailability.nearestInterval(start: time(9, 30), end: time(10, 30), occupied: [DateInterval(start: time(10), end: time(12))], calendar: calendar)
        #expect(closerBefore == DateInterval(start: time(9), end: time(10)))
    }

    @Test func suggestionClipsMidnightMergesBusyIntervalsAndPreservesDuration() {
        let occupied = [DateInterval(start: time(23, day: 16), end: time(2)), DateInterval(start: time(1), end: time(3)), DateInterval(start: time(3), end: time(4))]
        let suggestion = SessionAvailability.nearestInterval(start: time(1), end: time(2, 30), occupied: occupied, calendar: calendar)
        #expect(suggestion == DateInterval(start: time(4), end: time(5, 30)))
        #expect(suggestion?.duration == 5400)
    }

    @Test func suggestionReturnsNoneForFullDayRunningOrInvalidDuration() {
        let allDay = [DateInterval(start: time(0), end: .distantFuture)]
        #expect(SessionAvailability.nearestInterval(start: time(10), end: time(11), occupied: allDay, calendar: calendar) == nil)
        #expect(SessionAvailability.nearestInterval(start: time(10), end: time(10), occupied: [], calendar: calendar) == nil)
        #expect(SessionAvailability.nearestInterval(start: time(10), end: time(9), occupied: [], calendar: calendar) == nil)
        #expect(SessionAvailability.nearestInterval(start: time(0), end: time(1, day: 18), occupied: [], calendar: calendar) == nil)
    }

    @Test func formShowsConflictsAppliesSuggestionWithoutSavingAndRevalidates() throws {
        let context = makeInMemoryContext()
        let repository = SessionRepository(modelContext: context)
        let project = Project(name: "P", client: "C", dailyRate: 0, category: .work)
        let busy = Session(project: project, date: time(10), startTime: time(10), endTime: time(11), category: .work, status: .completed)
        try repository.insert(busy)
        let form = SessionFormViewModel(project: project, sessionRepository: repository, calendar: calendar)
        form.startTime = time(10)
        form.endTime = time(11)
        #expect(form.conflictingSessions.map(\.id) == [busy.id])
        #expect(form.suggestedInterval == DateInterval(start: time(11), end: time(12)))
        #expect(form.save() == false)
        form.applySuggestedInterval()
        #expect(form.startTime == time(11))
        #expect(form.endTime == time(12))
        #expect(form.date == time(0))
        #expect(try repository.fetchAll(for: nil).count == 1)
        try repository.insert(Session(project: project, date: time(11), startTime: time(11), endTime: time(12), category: .work, status: .completed))
        #expect(form.save() == false)
        #expect(form.conflictingSessions.count == 1)
    }

    @Test func formKeepsDateAndTimesCoherentPreservingDuration() throws {
        let repository = SessionRepository(modelContext: makeInMemoryContext())
        let project = Project(name: "P", client: "C", dailyRate: 0, category: .work)
        let form = SessionFormViewModel(project: project, sessionRepository: repository, calendar: calendar)
        form.startTime = time(23)
        form.endTime = time(1, day: 18)
        form.date = time(0, day: 19)
        #expect(form.startTime == time(23, day: 19))
        #expect(form.endTime == time(1, day: 20))
        form.startTime = time(10)
        #expect(form.date == time(0))
        form.endTime = time(9)
        #expect(form.suggestedInterval == nil)
        #expect(form.conflictingSessions.isEmpty)
    }

    @Test func saveStoresStartDayAfterDateChangeAndSuggestion() throws {
        let repository = SessionRepository(modelContext: makeInMemoryContext())
        let project = Project(name: "P", client: "C", dailyRate: 0, category: .work)
        let form = SessionFormViewModel(project: project, sessionRepository: repository, calendar: calendar)
        form.startTime = time(10)
        form.endTime = time(11)
        form.date = time(14, day: 19)
        #expect(form.save())
        let saved = try #require(repository.fetchAll(for: nil).first)
        #expect(saved.date == time(0, day: 19))
        #expect(saved.startTime == time(10, day: 19))
        #expect(saved.endTime == time(11, day: 19))
        #expect(saved.durationSeconds == 3600)
        #expect(saved.status == .completed)
    }

    @Test func suggestionUsesActualDSTDayLength() {
        var daylightCalendar = Calendar(identifier: .gregorian)
        daylightCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        let day = daylightCalendar.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        #expect(daylightCalendar.dateInterval(of: .day, for: day)?.duration == TimeInterval(82800))
        #expect(SessionAvailability.nearestInterval(start: day, end: day.addingTimeInterval(24 * 3600), occupied: [], calendar: daylightCalendar) == nil)
    }

    @Test func editingExcludesItselfAndIncludesCrossingMidnightInSuggestions() throws {
        let repository = SessionRepository(modelContext: makeInMemoryContext())
        let project = Project(name: "P", client: "C", dailyRate: 0, category: .work)
        let editing = Session(project: project, date: time(0), startTime: time(0), endTime: time(1), category: .work, status: .completed)
        try repository.insert(editing)
        let form = SessionFormViewModel(project: project, sessionRepository: repository, calendar: calendar, editing: editing)
        #expect(form.conflictingSessions.isEmpty)
        let crossing = Session(project: project, date: time(23, day: 16), startTime: time(23, day: 16), endTime: time(2), category: .work, status: .completed)
        try repository.insert(crossing)
        form.refreshAvailability()
        #expect(form.conflictingSessions.map(\.id) == [crossing.id])
        #expect(form.suggestedInterval == DateInterval(start: time(2), end: time(3)))
    }
}


@MainActor
struct SessionConflictRenderingTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["WORKLOG_SESSION_PREVIEW_DIR"] != nil))
    func renderConflictStatesWithSyntheticData() throws {
        guard let output = ProcessInfo.processInfo.environment["WORKLOG_SESSION_PREVIEW_DIR"] else { return }
        try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
        _ = NSApplication.shared
        let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1792191600))
        let start = day.addingTimeInterval(10 * 3600)
        let project = Project(name: "Projeto com nome longo para validar a leitura dos conflitos de horário", client: "Cliente de teste", dailyRate: 0, category: .work)
        let secondProject = Project(name: "Outro projeto", client: "Cliente de teste", dailyRate: 0, category: .work)
        let busy = Session(project: project, date: day, startTime: start, endTime: start.addingTimeInterval(3600), category: .work, status: .completed)
        let running = Session(project: secondProject, date: day, startTime: start.addingTimeInterval(900), category: .work, status: .running)
        for (name, sessions, suggestion) in [
            ("session-conflict-suggestion", [busy], Optional(DateInterval(start: start.addingTimeInterval(3600), duration: 3600))),
            ("session-conflict-running-no-space", [busy, running], nil)
        ] {
            let content = Form {
                Section("Período") {
                    DatePicker("Data", selection: .constant(day), displayedComponents: .date)
                    DatePicker("Início", selection: .constant(start))
                    DatePicker("Fim", selection: .constant(start.addingTimeInterval(3600)))
                }
                SessionConflictSection(sessions: sessions, suggestedInterval: suggestion, onApply: {})
                Section("Observação") { Text("Nota de teste") }
            }
            .formStyle(.grouped)
            .environment(\.locale, Locale(identifier: "pt_BR"))
            .frame(width: 480, height: 620)
            let host = NSHostingView(rootView: content)
            host.frame = NSRect(x: 0, y: 0, width: 480, height: 620)
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: output).appendingPathComponent("\(name).png"))
            #expect(png.count > 3000)
        }
    }
}


@MainActor
struct ResumedSessionIntegrationTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private func time(_ hour: Int, day: Int = 17) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }
    private func resumed(project: Project, status: SessionStatus = .paused) -> Session {
        let session = Session(project: project, date: time(0), startTime: time(9),
            endTime: time(13), durationSeconds: 7200, category: .work, status: status)
        session.workPeriods = [.init(start: time(9), end: time(10)), .init(start: time(12), end: time(13))]
        return session
    }

    @Test func resumedSessionLeavesPauseFreeAndFindsLaterWorkAcrossDays() throws {
        let repository = SessionRepository(modelContext: makeInMemoryContext())
        let project = Project(name: "P", client: "C", dailyRate: 800, category: .work)
        let session = resumed(project: project)
        session.workPeriods = [.init(start: time(9), end: time(10)), .init(start: time(12, day: 18), end: time(13, day: 18))]
        session.endTime = time(13, day: 18)
        try repository.insert(session)
        #expect(try !repository.hasOverlap(start: time(10), end: time(12, day: 18), excluding: nil))
        #expect(try repository.hasOverlap(start: time(12, day: 18), end: time(13, day: 18), excluding: nil))
        #expect(try repository.fetchSessions(in: DateInterval(start: time(0, day: 18), end: time(0, day: 19))).map(\.id) == [session.id])
        #expect(try repository.fetchSessions(in: DateInterval(start: time(10), end: time(12))).isEmpty)
    }

    @Test func suggestionUsesGapBetweenPeriodsAndOpenPeriodBlocksFuture() throws {
        let repository = SessionRepository(modelContext: makeInMemoryContext())
        let project = Project(name: "P", client: "C", dailyRate: 0, category: .work)
        let session = resumed(project: project, status: .running)
        session.endTime = nil
        session.workPeriods = [.init(start: time(9), end: time(10)), .init(start: time(12), end: nil)]
        try repository.insert(session)
        let form = SessionFormViewModel(project: project, sessionRepository: repository, calendar: calendar)
        form.startTime = time(9)
        form.endTime = time(10)
        #expect(form.suggestedInterval == DateInterval(start: time(10), end: time(11)))
        #expect(try repository.hasOverlap(start: time(20), end: time(21), excluding: nil))
    }

    @Test func multiPeriodEditorUnlocksWithoutChangingDraftAndRunningSessionCannotSave() throws {
        let repository = SessionRepository(modelContext: makeInMemoryContext())
        let project = Project(name: "P", client: "C", dailyRate: 0, category: .work)
        let session = resumed(project: project)
        try repository.insert(session)
        let originalPeriods = session.workPeriods
        let form = SessionFormViewModel(project: project, sessionRepository: repository, calendar: calendar, editing: session)
        #expect(!form.isTimeEditingLocked)
        #expect(form.note == session.note)
        #expect(session.workPeriods == originalPeriods)
        form.startTime = time(8)
        form.endTime = time(14)
        form.note = "Observação corrigida"
        #expect(form.save())
        #expect(session.note == "Observação corrigida")
        #expect(session.startTime == time(9))
        #expect(session.endTime == time(13))
        #expect(session.durationSeconds == 7200)
        #expect(session.workPeriods == originalPeriods)
        #expect(session.status == .paused)
        session.status = .running
        form.note = "Não salvar durante execução"
        #expect(!form.save())
        #expect(session.note == "Observação corrigida")
    }

    @Test func recentSessionsUseLastWorkedPeriodInsteadOfOriginalStart() throws {
        let repository = SessionRepository(modelContext: makeInMemoryContext())
        let project = Project(name: "P", client: "C", dailyRate: 0, category: .work)
        let resumed = resumed(project: project)
        let other = Session(project: project, date: time(0), startTime: time(11), endTime: time(12), durationSeconds: 3600, category: .work, status: .completed)
        try repository.insert(resumed)
        try repository.insert(other)
        #expect(try repository.fetchRecent(limit: 1).first?.id == resumed.id)
    }

    @Test func reportsAndBillingClipClosedPeriodsByDayWhileSessionRuns() throws {
        func localTime(_ hour: Int, day: Int = 17) -> Date {
            Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
        }
        let context = makeInMemoryContext()
        let projects = ProjectRepository(modelContext: context)
        let repository = SessionRepository(modelContext: context)
        let settings = SettingsRepository(modelContext: context)
        let project = Project(name: "P", client: "C", dailyRate: 800, category: .work)
        try projects.insert(project)
        let session = resumed(project: project, status: .running)
        session.endTime = nil
        session.workPeriods = [.init(start: localTime(23), end: localTime(1, day: 18)), .init(start: localTime(4, day: 18), end: localTime(5, day: 18)), .init(start: localTime(7, day: 18), end: nil)]
        session.durationSeconds = 10800
        try repository.insert(session)
        let start = localTime(0, day: 18)
        let end = localTime(6, day: 18)
        let reports = ReportsViewModel(sessionRepository: repository, exportService: ExportService())
        reports.customStart = start
        reports.customEnd = end
        reports.period = .custom
        #expect(reports.sessions.map(\.id) == [session.id])
        #expect(reports.totalDuration == 7200)
        #expect(reports.totalValue == 200)
        #expect(reports.reportRows().reduce(0) { $0 + $1.durationSeconds } == 7200)
        reports.grouping = .byProjectAndDay
        #expect(reports.reportRows().count == 1)
        #expect(reports.reportRows().first?.sessionCount == 1)
        let billing = BillingViewModel(projectRepository: projects, sessionRepository: repository,
            invoiceRepository: InvoiceRepository(modelContext: context, settingsRepository: settings), settingsRepository: settings, exportService: ExportService())
        billing.customStart = start
        billing.customEnd = end
        billing.selectedClient = "C"
        billing.period = .custom
        #expect(billing.previewLineItems.count == 1)
        #expect(billing.previewTotalDuration == 7200)
        #expect(billing.previewTotalValue == 200)
        #expect(try repository.fetchAll(for: nil).count == 1)
    }

    @Test func projectTotalsKeepClosedWorkWhenPausedSessionResumes() throws {
        let context = makeInMemoryContext()
        let projects = ProjectRepository(modelContext: context)
        let repository = SessionRepository(modelContext: context)
        let project = Project(name: "P", client: "C", dailyRate: 2880, category: .work)
        try projects.insert(project)
        let end = Date.now.addingTimeInterval(-60)
        let session = Session(project: project, date: end, startTime: end.addingTimeInterval(-600),
            endTime: end, durationSeconds: 600, category: .work, status: .paused)
        try repository.insert(session)
        let expectedValue = session.estimatedValue
        #expect(expectedValue > 0)
        #expect(project.totalWorkedSeconds == 600)
        #expect(project.totalValue == expectedValue)
        let timer = TimerService(sessionRepository: repository, projectRepository: projects,
            idleDetectionService: IdleDetectionService(idleThresholdMinutes: 10))
        try timer.resume(project: project)
        #expect(timer.activeSession?.id == session.id)
        #expect(project.totalWorkedSeconds == 600)
        #expect(project.totalValue == expectedValue)
        try timer.stop()
    }

    @Test func dashboardAndNotchKeepClosedTimeWhileSameSessionRuns() throws {
        let context = makeInMemoryContext()
        let projects = ProjectRepository(modelContext: context)
        let repository = SessionRepository(modelContext: context)
        let settings = SettingsRepository(modelContext: context)
        let project = Project(name: "P", client: "C", dailyRate: 0, category: .work)
        try projects.insert(project)
        let today = Calendar.current.startOfDay(for: .now)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let session = Session(project: project, date: yesterday, startTime: yesterday,
            durationSeconds: 7200, category: .work, status: .running)
        session.workPeriods = [.init(start: yesterday, end: yesterday.addingTimeInterval(3600)),
            .init(start: today, end: today.addingTimeInterval(3600)), .init(start: .now, end: nil)]
        try repository.insert(session)
        let dashboard = DashboardViewModel(projectRepository: projects, sessionRepository: repository)
        #expect(dashboard.todayTotal == 3600)
        #expect(dashboard.allTimeTotal == 7200)
        let timer = TimerService(sessionRepository: repository, projectRepository: projects, idleDetectionService: IdleDetectionService(idleThresholdMinutes: 10))
        let notch = NotchPanelViewModel(timerService: timer, projectRepository: projects, sessionRepository: repository, settingsRepository: settings)
        #expect(notch.todayTotal == 3600)
        let menu = MenuBarViewModel(timerService: timer, projectRepository: projects,
            sessionRepository: repository, settingsRepository: settings)
        #expect(menu.todayTotal == 3600)
    }
}

@MainActor
struct SessionCycleEditorTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private func time(_ hour: Int, _ minute: Int = 0, day: Int = 17) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }
    private func session(project: Project, status: SessionStatus = .paused) -> Session {
        let session = Session(project: project, date: time(0), startTime: time(9), endTime: time(16),
            durationSeconds: 10800, note: "Nota original", category: .work, status: status)
        session.workPeriods = [.init(start: time(9), end: time(10)), .init(start: time(12), end: time(13)),
            .init(start: time(15), end: time(16))]
        return session
    }

    @Test func editsMiddleCycleWithoutChangingNeighborsIdentityStatusOrCount() throws {
        for status in [SessionStatus.paused, .completed] {
            let repository = SessionRepository(modelContext: makeInMemoryContext())
            let project = Project(name: "P", client: "C", dailyRate: 800, category: .work)
            let session = session(project: project, status: status)
            try repository.insert(session)
            let id = session.id
            let originals = session.workPeriods
            let form = SessionFormViewModel(project: project, sessionRepository: repository, calendar: calendar, editing: session)
            #expect(form.usesCycleEditor)
            #expect(!form.isTimeEditingLocked)
            form.updateCycleStart(at: 1, to: time(11, 30))
            form.note = "Corrigida"
            #expect(session.workPeriods == originals)
            #expect(session.note == "Nota original")
            #expect(form.cyclesTotal == 12600)
            #expect(form.save())
            #expect(session.id == id)
            #expect(try repository.fetchAll(for: nil).map(\.id) == [id])
            #expect(session.workPeriods.count == 3)
            #expect(session.workPeriods[0] == originals[0])
            #expect(session.workPeriods[2] == originals[2])
            #expect(session.workPeriods[1] == SessionWorkPeriod(start: time(11, 30), end: time(13)))
            #expect(session.durationSeconds == 12600)
            #expect(session.estimatedValue == 350)
            #expect(session.note == "Corrigida")
            #expect(session.status == status)
            #expect(session.startTime == time(9))
            #expect(session.endTime == time(16))
        }
    }

    @Test func rejectsInvalidAndOverlappingCyclesWithoutMutatingSession() throws {
        let repository = SessionRepository(modelContext: makeInMemoryContext())
        let project = Project(name: "P", client: "C", dailyRate: 0, category: .work)
        let session = session(project: project)
        try repository.insert(session)
        let original = session.workPeriods
        let form = SessionFormViewModel(project: project, sessionRepository: repository, calendar: calendar, editing: session)
        form.note = "Não salvar"
        form.updateCycleEnd(at: 1, to: time(12))
        #expect(form.cycleValidationMessage?.contains("Ciclo 2") == true)
        #expect(!form.save())
        form.updateCycleEnd(at: 1, to: time(13))
        form.updateCycleStart(at: 1, to: time(9, 30))
        #expect(form.cycleValidationMessage?.contains("Ciclo 2") == true)
        #expect(!form.save())
        form.updateCycleStart(at: 1, to: time(12))
        form.updateCycleEnd(at: 1, to: time(15, 1))
        #expect(form.cycleValidationMessage?.contains("Ciclo 3") == true)
        #expect(!form.save())
        #expect(session.workPeriods == original)
        #expect(session.durationSeconds == 10800)
        #expect(session.note == "Nota original")
    }

    @Test func allowsAdjacentCyclesAndOtherWorkInsidePauseButRevalidatesExternalConflictAtSave() throws {
        let repository = SessionRepository(modelContext: makeInMemoryContext())
        let project = Project(name: "P", client: "C", dailyRate: 0, category: .work)
        let otherProject = Project(name: "Projeto externo", client: "C", dailyRate: 0, category: .work)
        let session = session(project: project)
        try repository.insert(session)
        try repository.insert(Session(project: otherProject, date: time(0), startTime: time(10), endTime: time(11),
            durationSeconds: 3600, category: .work, status: .completed))
        let form = SessionFormViewModel(project: project, sessionRepository: repository, calendar: calendar, editing: session)
        form.updateCycleStart(at: 1, to: time(11))
        form.updateCycleEnd(at: 1, to: time(15))
        #expect(form.cycleValidationMessage == nil)
        #expect(form.suggestedInterval == nil)
        #expect(form.save())
        #expect(session.durationSeconds == 21600)
        let original = session.workPeriods
        let staleAvailability = SessionFormViewModel(project: project, sessionRepository: repository, calendar: calendar, editing: session)
        staleAvailability.updateCycleStart(at: 0, to: time(8))
        let conflict = Session(project: otherProject, date: time(0), startTime: time(8), endTime: time(9),
            durationSeconds: 3600, category: .work, status: .completed)
        try repository.insert(conflict)
        #expect(!staleAvailability.save())
        #expect(staleAvailability.cycleValidationMessage?.contains("Ciclo 1") == true)
        #expect(staleAvailability.cycleValidationMessage?.contains("Projeto externo") == true)
        #expect(staleAvailability.cycleValidationMessage?.contains("08:00:00") == true)
        #expect(staleAvailability.conflictingSessions.map(\.id) == [conflict.id])
        #expect(staleAvailability.suggestedInterval == nil)
        #expect(session.workPeriods == original)
    }

    @Test func updatesEnvelopeAndDayAcrossMidnightWithoutCountingPause() throws {
        let repository = SessionRepository(modelContext: makeInMemoryContext())
        let project = Project(name: "P", client: "C", dailyRate: 0, category: .work)
        let session = session(project: project)
        try repository.insert(session)
        let form = SessionFormViewModel(project: project, sessionRepository: repository, calendar: calendar, editing: session)
        form.updateCycleStart(at: 0, to: time(23, day: 18))
        form.updateCycleEnd(at: 0, to: time(1, day: 19))
        form.updateCycleStart(at: 1, to: time(2, day: 19))
        form.updateCycleEnd(at: 1, to: time(3, day: 19))
        form.updateCycleStart(at: 2, to: time(5, day: 19))
        form.updateCycleEnd(at: 2, to: time(5, 30, day: 19))
        #expect(form.cyclesTotal == 12600)
        #expect(form.save())
        #expect(session.date == time(0, day: 18))
        #expect(session.startTime == time(23, day: 18))
        #expect(session.endTime == time(5, 30, day: 19))
        #expect(session.durationSeconds == 12600)
        #expect(try !repository.hasOverlap(start: time(1, day: 19), end: time(2, day: 19), excluding: nil))
    }

    @Test func abandoningDraftDoesNotChangePersistedCyclesOrNote() throws {
        let repository = SessionRepository(modelContext: makeInMemoryContext())
        let project = Project(name: "P", client: "C", dailyRate: 0, category: .work)
        let session = session(project: project)
        try repository.insert(session)
        let original = session.workPeriods
        do {
            let form = SessionFormViewModel(project: project, sessionRepository: repository, calendar: calendar, editing: session)
            form.updateCycleStart(at: 0, to: time(8))
            form.updateCycleEnd(at: 2, to: time(17))
            form.note = "Rascunho descartado"
        }
        let reloaded = try #require(repository.fetchAll(for: nil).first)
        #expect(reloaded.workPeriods == original)
        #expect(reloaded.note == "Nota original")
        #expect(reloaded.durationSeconds == 10800)
    }

    @Test func rejectsDeletedChangedOrResumedSessionWithoutOverwritingCurrentData() throws {
        for change in ["delete", "periods", "resume", "status"] {
            let repository = SessionRepository(modelContext: makeInMemoryContext())
            let project = Project(name: "P", client: "C", dailyRate: 0, category: .work)
            let session = session(project: project)
            try repository.insert(session)
            let form = SessionFormViewModel(project: project, sessionRepository: repository, calendar: calendar, editing: session)
            form.updateCycleStart(at: 0, to: time(8))
            form.note = "Rascunho obsoleto"
            if change == "delete" {
                try repository.delete(session)
                #expect(!form.save())
                #expect(form.errorMessage?.contains("removida") == true)
                #expect(try repository.fetchAll(for: nil).isEmpty)
            } else {
                if change == "periods" { session.workPeriods[1].start = time(11) }
                if change == "resume" {
                    session.status = .running
                    session.endTime = nil
                    session.workPeriods.append(.init(start: time(18), end: nil))
                }
                if change == "status" { session.status = .completed }
                try repository.update(session)
                let current = session.workPeriods
                #expect(!form.save())
                #expect(form.errorMessage != nil)
                #expect(session.workPeriods == current)
                #expect(session.note == "Nota original")
                #expect(session.startTime == time(9))
            }
        }
    }

    @Test func runningSessionLocksCycleUpdatesAndCannotSave() throws {
        let repository = SessionRepository(modelContext: makeInMemoryContext())
        let project = Project(name: "P", client: "C", dailyRate: 0, category: .work)
        let session = session(project: project, status: .running)
        session.workPeriods[2].end = nil
        session.endTime = nil
        try repository.insert(session)
        let original = session.workPeriods
        let form = SessionFormViewModel(project: project, sessionRepository: repository, calendar: calendar, editing: session)
        #expect(form.isTimeEditingLocked)
        form.updateCycleStart(at: 0, to: time(8))
        form.updateCycleEnd(at: 2, to: time(17))
        #expect(form.cyclePeriods == original)
        #expect(!form.save())
        #expect(session.workPeriods == original)
    }

    @Test func savedCycleEditsBecomeAccumulatedTimeWhenSameSessionResumes() throws {
        let context = makeInMemoryContext()
        let repository = SessionRepository(modelContext: context)
        let projects = ProjectRepository(modelContext: context)
        let project = Project(name: "P", client: "C", dailyRate: 800, category: .work)
        try projects.insert(project)
        let session = session(project: project)
        try repository.insert(session)
        let form = SessionFormViewModel(project: project, sessionRepository: repository, calendar: calendar, editing: session)
        form.updateCycleStart(at: 1, to: time(11, 30))
        #expect(form.save())
        let saved = session.workPeriods
        let timer = TimerService(sessionRepository: repository, projectRepository: projects,
            idleDetectionService: IdleDetectionService(idleThresholdMinutes: 10))
        try timer.resume(project: project)
        #expect(timer.activeSession?.id == session.id)
        #expect(session.status == .running)
        #expect(session.durationSeconds == 12600)
        #expect(session.workPeriods.count == 4)
        #expect(Array(session.workPeriods.prefix(3)) == saved)
        #expect(session.workPeriods.last?.end == nil)
        #expect(timer.elapsed >= 12600)
        #expect(try repository.fetchAll(for: nil).count == 1)
        try timer.stop()
    }
}
