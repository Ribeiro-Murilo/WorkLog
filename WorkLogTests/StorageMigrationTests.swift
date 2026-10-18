import Foundation
import SwiftData
import Testing
@testable import WorkLog

@MainActor
private let migrationTestContainers: (source: ModelContainer, destination: ModelContainer) = {
    let schema = PersistenceController.schema()
    let sourceConfiguration = ModelConfiguration("migration-source", schema: schema, isStoredInMemoryOnly: true)
    let destinationConfiguration = ModelConfiguration("migration-destination", schema: schema, isStoredInMemoryOnly: true)
    return (
        try! ModelContainer(for: schema, configurations: [sourceConfiguration]),
        try! ModelContainer(for: schema, configurations: [destinationConfiguration])
    )
}()

@MainActor
struct StorageMigrationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["WORKLOG_RESUME_MIGRATION_STORE"] != nil))
    func legacyDiskStoreAddsOptionalWorkPeriodsWithoutChangingExistingRecords() throws {
        let environment = ProcessInfo.processInfo.environment
        let path = try #require(environment["WORKLOG_RESUME_MIGRATION_STORE"])
        let expectedSessions = try #require(environment["WORKLOG_RESUME_MIGRATION_SESSION_COUNT"].flatMap(Int.init))
        let expectedProjects = try #require(environment["WORKLOG_RESUME_MIGRATION_PROJECT_COUNT"].flatMap(Int.init))
        let input = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        let repository = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
        let allowedDirectory = repository.appendingPathComponent("build/local-test-resume-2026-10-18", isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        // Only consume the isolated, consistent backup prepared for this validation.
        #expect(input.deletingLastPathComponent() == allowedDirectory)
        guard input.deletingLastPathComponent() == allowedDirectory else { return }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WorkLog-legacy-schema-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let copiedStore = directory.appendingPathComponent("migration.store")
        let before = try Data(contentsOf: input)
        try FileManager.default.copyItem(at: input, to: copiedStore)
        let schema = PersistenceController.schema()
        let configuration = ModelConfiguration("legacy-session-validation", schema: schema, url: copiedStore, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let sessions = try context.fetch(FetchDescriptor<Session>())
        let projects = try context.fetch(FetchDescriptor<Project>())

        #expect(sessions.count == expectedSessions)
        #expect(projects.count == expectedProjects)
        #expect(Set(sessions.map(\.id)).count == expectedSessions)
        #expect(sessions.allSatisfy { $0.workPeriodsData == nil })
        #expect(sessions.allSatisfy { $0.workPeriods.count == 1 && $0.workPeriods.first?.start == $0.startTime })
        #expect(try Data(contentsOf: input) == before)
    }

    @Test func copiesAllEntitiesAndRelationships() throws {
        let (source, destination) = freshContexts()
        let project = Project(
            name: "Projeto legado",
            client: "Cliente",
            dailyRate: 800,
            category: .work,
            tags: ["legado"],
            descriptionText: "Descrição preservada",
            status: .inProgress,
            isFavorite: true
        )
        project.id = UUID()

        let session = Session(
            project: project,
            date: .now,
            startTime: .now.addingTimeInterval(-3600),
            endTime: .now,
            durationSeconds: 3600,
            note: "Sessão preservada",
            category: .work,
            status: .completed
        )
        session.id = UUID()
        session.workPeriods = [
            SessionWorkPeriod(start: session.startTime, end: session.startTime.addingTimeInterval(1200)),
            SessionWorkPeriod(start: session.startTime.addingTimeInterval(1800), end: session.startTime.addingTimeInterval(3600))
        ]
        session.durationSeconds = 3000

        let comment = WorkLog.Comment(text: "Comentário preservado", author: "Murilo", project: project)
        comment.id = UUID()

        let settings = AppSettings()
        settings.displayMode = .notch
        settings.lastInvoiceNumber = 7
        settings.invoiceIssuerName = "Ribeiro Workes"
        settings.includeLogoInPDF = true

        let shortcut = ShortcutBinding(
            action: .openDashboard,
            keyCombo: KeyCombo(keyCode: 40, modifiers: 1),
            isEnabled: false
        )

        let preset = ReportPreset(
            name: "Preset legado",
            columns: [.project, .duration],
            grouping: .byProjectAndDay
        )
        preset.id = UUID()

        let invoice = Invoice(
            number: 7,
            client: "Cliente",
            periodStart: .now.addingTimeInterval(-86400),
            periodEnd: .now,
            lineItems: [
                InvoiceLineItem(date: .now, projectName: project.name, durationSeconds: 3600, value: 100)
            ],
            notes: "Fatura preservada",
            status: .paid
        )
        invoice.id = UUID()

        source.insert(project)
        source.insert(session)
        source.insert(comment)
        source.insert(settings)
        source.insert(shortcut)
        source.insert(preset)
        source.insert(invoice)
        try source.save()

        let defaults = makeMigrationDefaults()
        let migrator = LegacyStorageMigrator(
            legacyStoreURL: URL(fileURLWithPath: "/tmp/worklog-test-legacy.store"),
            userDefaults: defaults
        )

        #expect(migrator.migrateIfNeeded(sourceContext: source, destinationContext: destination) == nil)

        let copiedProject = try destination.fetch(FetchDescriptor<Project>()).first
        let copiedSession = try destination.fetch(FetchDescriptor<Session>()).first
        let copiedComment = try destination.fetch(FetchDescriptor<WorkLog.Comment>()).first
        let copiedSettings = try destination.fetch(FetchDescriptor<AppSettings>()).first
        let copiedShortcut = try destination.fetch(FetchDescriptor<ShortcutBinding>()).first
        let copiedPreset = try destination.fetch(FetchDescriptor<ReportPreset>()).first
        let copiedInvoice = try destination.fetch(FetchDescriptor<Invoice>()).first

        #expect(copiedProject?.id == project.id)
        #expect(copiedProject?.tags == project.tags)
        #expect(copiedProject?.isFavorite == true)
        #expect(copiedSession?.id == session.id)
        #expect(copiedSession?.project?.id == project.id)
        #expect(copiedSession?.workPeriodsData == session.workPeriodsData)
        #expect(copiedSession?.workPeriods == session.workPeriods)
        #expect(copiedSession?.durationSeconds == 3000)
        #expect(copiedComment?.id == comment.id)
        #expect(copiedComment?.project?.id == project.id)
        #expect(copiedSettings?.displayMode == .notch)
        #expect(copiedSettings?.lastInvoiceNumber == 7)
        #expect(copiedShortcut?.actionRawValue == ShortcutAction.openDashboard.rawValue)
        #expect(copiedShortcut?.isEnabled == false)
        #expect(copiedPreset?.id == preset.id)
        #expect(copiedPreset?.columnsRaw == preset.columnsRaw)
        #expect(copiedInvoice?.id == invoice.id)
        #expect(copiedInvoice?.lineItems == invoice.lineItems)
        #expect(defaults.bool(forKey: LegacyStorageMigrator.completionKey))
    }

    @Test func workPeriodsSurviveClosingAndReopeningTemporaryDiskStore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WorkLog-session-persistence-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = PersistenceController.schema()
        let configuration = ModelConfiguration("session-persistence", schema: schema, url: directory.appendingPathComponent("test.store"), cloudKitDatabase: .none)
        let start = Date(timeIntervalSinceReferenceDate: 100)
        let expected = [
            SessionWorkPeriod(start: start, end: start.addingTimeInterval(10)),
            SessionWorkPeriod(start: start.addingTimeInterval(30), end: nil)
        ]
        let id: UUID = try autoreleasepool {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let session = Session(project: nil, date: start, startTime: start, durationSeconds: 10, note: "same session", category: .work)
            session.workPeriods = expected
            context.insert(session)
            try context.save()
            return session.id
        }

        let reopened = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(reopened)
        let sessions = try context.fetch(FetchDescriptor<Session>())
        #expect(sessions.count == 1)
        let restored = try #require(sessions.first)
        #expect(restored.id == id)
        #expect(restored.startTime == start)
        #expect(restored.workPeriods == expected)
        #expect(restored.durationSeconds == 10)
        #expect(restored.note == "same session")
        #expect(restored.status == .running)
    }

    @Test func migrationIsIdempotent() throws {
        let (source, destination) = freshContexts()
        let project = Project(name: "Projeto", client: "Cliente", dailyRate: 100, category: .work)
        source.insert(project)
        try source.save()

        let defaults = makeMigrationDefaults()
        let migrator = LegacyStorageMigrator(userDefaults: defaults)

        #expect(migrator.migrateIfNeeded(sourceContext: source, destinationContext: destination) == nil)
        #expect(migrator.migrateIfNeeded(sourceContext: source, destinationContext: destination) == nil)
        #expect(try destination.fetch(FetchDescriptor<Project>()).count == 1)
    }

    @Test func refusesToMergeWhenDestinationAlreadyHasData() throws {
        let (source, destination) = freshContexts()
        source.insert(Project(name: "Legado", client: "Cliente", dailyRate: 100, category: .work))
        destination.insert(Project(name: "Atual", client: "Cliente", dailyRate: 100, category: .work))
        try source.save()
        try destination.save()

        let defaults = makeMigrationDefaults()
        let migrator = LegacyStorageMigrator(userDefaults: defaults)
        let notice = migrator.migrateIfNeeded(sourceContext: source, destinationContext: destination)

        #expect(notice?.kind == .conflict)
        #expect(try destination.fetch(FetchDescriptor<Project>()).map(\.name) == ["Atual"])
        #expect(!defaults.bool(forKey: LegacyStorageMigrator.completionKey))
    }

    @Test func skipsEmptyLegacyStore() throws {
        let (source, destination) = freshContexts()
        let defaults = makeMigrationDefaults()
        let migrator = LegacyStorageMigrator(userDefaults: defaults)

        #expect(migrator.migrateIfNeeded(sourceContext: source, destinationContext: destination) == nil)
        #expect(try destination.fetch(FetchDescriptor<Project>()).isEmpty)
        #expect(!defaults.bool(forKey: LegacyStorageMigrator.completionKey))
    }

    @Test func treatsDefaultShortcutsAsEmptyDestination() throws {
        let (source, destination) = freshContexts()
        source.insert(Project(name: "Legado", client: "Cliente", dailyRate: 100, category: .work))
        try source.save()

        for action in ShortcutAction.allCases {
            guard let keyCombo = ShortcutsService.defaultBindings[action] else { continue }
            destination.insert(ShortcutBinding(action: action, keyCombo: keyCombo))
        }
        try destination.save()

        let defaults = makeMigrationDefaults()
        let migrator = LegacyStorageMigrator(userDefaults: defaults)
        #expect(migrator.migrateIfNeeded(sourceContext: source, destinationContext: destination) == nil)
        #expect(try destination.fetch(FetchDescriptor<Project>()).count == 1)
        #expect(try destination.fetch(FetchDescriptor<ShortcutBinding>()).count == ShortcutAction.allCases.count)
    }

    private func freshContexts() -> (ModelContext, ModelContext) {
        let source = ModelContext(migrationTestContainers.source)
        let destination = ModelContext(migrationTestContainers.destination)
        reset(source)
        reset(destination)
        return (source, destination)
    }

    private func reset(_ context: ModelContext) {
        try? context.delete(model: WorkLog.Comment.self)
        try? context.delete(model: Session.self)
        try? context.delete(model: Project.self)
        try? context.delete(model: AppSettings.self)
        try? context.delete(model: ShortcutBinding.self)
        try? context.delete(model: ReportPreset.self)
        try? context.delete(model: Invoice.self)
        try? context.save()
        context.rollback()
    }

    private func makeMigrationDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: "WorkLog.StorageMigrationTests")!
        defaults.removeObject(forKey: LegacyStorageMigrator.completionKey)
        return defaults
    }
}
