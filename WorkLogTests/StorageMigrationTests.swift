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
