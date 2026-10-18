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
