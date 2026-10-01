import Foundation
import SwiftData
import Testing
@testable import WorkLog

@MainActor
private let syncStoreContainer: ModelContainer = {
    let schema = PersistenceController.schema()
    return try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
}()

@MainActor
private let secondSyncStoreContainer: ModelContainer = {
    let schema = PersistenceController.schema()
    return try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
}()

@MainActor
func makeSyncRecordContext() throws -> ModelContext {
    let context = ModelContext(syncStoreContainer)
    context.autosaveEnabled = false
    try context.delete(model: Session.self)
    try context.delete(model: WorkLog.Comment.self)
    try context.delete(model: Project.self)
    try context.delete(model: ReportPreset.self)
    try context.delete(model: Invoice.self)
    try context.delete(model: ShortcutBinding.self)
    try context.delete(model: AppSettings.self)
    try context.delete(model: FolderSyncMetadata.self)
    try context.save()
    return context
}

@Suite(.serialized) @MainActor
struct SyncRecordStoreTests {
    @Test func closedRecordsRoundTripAndMachinePreferencesStayLocal() throws {
        let context = try makeSyncRecordContext()
        let project = Project(name: "Alpha", client: "Acme", dailyRate: Decimal(string: "123.45")!, category: .personal, tags: ["tag"], descriptionText: "full", status: .blocked, isArchived: true, isFavorite: true)
        project.createdAt = Date(timeIntervalSinceReferenceDate: 123.123456)
        let expectedDate = project.createdAt
        context.insert(project)
        let closed = Session(project: project, date: project.createdAt, startTime: project.createdAt, endTime: project.createdAt.addingTimeInterval(10), durationSeconds: 10, note: "note", category: .personal, status: .paused)
        context.insert(closed)
        context.insert(Session(project: project, date: .now, startTime: .now, category: .work))
        context.insert(WorkLog.Comment(text: "comment", author: "author", project: project))
        context.insert(ReportPreset(name: "Preset", columns: [], grouping: .detailed))
        let invoice = Invoice(number: 42, client: "Acme", periodStart: .now, periodEnd: .now, lineItems: [InvoiceLineItem(date: project.createdAt, projectName: "Frozen name", durationSeconds: 10, value: 999)])
        invoice.totalValue = 998
        context.insert(invoice)
        let settings = AppSettings(launchAtLogin: false, invoiceIssuerName: "Issuer", invoiceIssuerDetails: "PIX")
        settings.includeLogoInPDF = true
        context.insert(settings)
        context.insert(ShortcutBinding(action: .pauseTimer, keyCombo: KeyCombo(keyCode: 9, modifiers: 12)))
        try context.save()
        let store = SwiftDataSyncRecordStore(modelContext: context)
        let original = try store.snapshot()
        #expect(original.keys.filter { $0.entity == .session }.count == 1)
        #expect(original.values.allSatisfy { !$0.isEmpty })
        let receiver = ModelContext(secondSyncStoreContainer)
        receiver.autosaveEnabled = false
        try receiver.delete(model: Session.self); try receiver.delete(model: WorkLog.Comment.self); try receiver.delete(model: Project.self)
        try receiver.delete(model: Invoice.self); try receiver.delete(model: ReportPreset.self)
        try receiver.delete(model: AppSettings.self); try receiver.delete(model: ShortcutBinding.self)
        try receiver.delete(model: FolderSyncMetadata.self)
        let receiverSettings = AppSettings(launchAtLogin: true, idleTimeoutMinutes: 37)
        receiver.insert(receiverSettings)
        receiver.insert(ShortcutBinding(action: .startTimer, keyCombo: KeyCombo(keyCode: 11, modifiers: 1)))
        try receiver.save()
        let receiverStore = SwiftDataSyncRecordStore(modelContext: receiver)
        #expect(try receiverStore.snapshot().isEmpty)
        try receiverStore.apply(original.map { SyncRecordChange(key: $0.key, payload: $0.value) })
        try receiverStore.saveState(FolderSyncState(), scope: "roundtrip")
        #expect(try receiverStore.snapshot() == original)
        #expect(receiverSettings.launchAtLogin)
        #expect(receiverSettings.idleTimeoutMinutes == 37)
        #expect(receiverSettings.includeLogoInPDF == false)
        #expect(try receiver.fetch(FetchDescriptor<ShortcutBinding>()).first?.action == .startTimer)
        #expect(try receiver.fetch(FetchDescriptor<Invoice>()).first?.totalValue == 998)
        #expect(try receiver.fetch(FetchDescriptor<Project>()).first?.createdAt == expectedDate)
        let receivedProject = try #require(receiver.fetch(FetchDescriptor<Project>()).first)
        receivedProject.name = "Edited on second bank"; try receiver.save()
        let secondSnapshot = try receiverStore.snapshot()
        try store.apply(secondSnapshot.map { SyncRecordChange(key: $0.key, payload: $0.value) })
        try store.saveState(FolderSyncState(), scope: "return")
        #expect(project.name == "Edited on second bank")
        #expect(try context.fetch(FetchDescriptor<Session>()).filter { $0.status == .running }.count == 1)
        #expect(settings.launchAtLogin == false && settings.includeLogoInPDF)
    }

    @Test func incomingMissingParentRollsBackWholeBatchAndCheckpoint() throws {
        let context = try makeSyncRecordContext()
        let store = SwiftDataSyncRecordStore(modelContext: context)
        let missing = Project(name: "Missing", client: "", dailyRate: 0, category: .work)
        let session = Session(project: missing, date: .now, startTime: .now, category: .work, status: .completed)
        let preset = ReportPreset(name: "Must rollback", columns: [], grouping: .detailed)
        let changes = [SyncRecordChange(key: SyncRecordKey(entity: .reportPreset, id: preset.id.uuidString), payload: try SyncPayloadCodec.encode(ReportPresetSyncPayload(preset))), SyncRecordChange(key: SyncRecordKey(entity: .session, id: session.id.uuidString), payload: try SyncPayloadCodec.encode(SessionSyncPayload(session)))]
        #expect(throws: (any Error).self) { try store.apply(changes) }
        #expect(try context.fetch(FetchDescriptor<ReportPreset>()).isEmpty)
        #expect(try store.loadState(scope: "missing") == nil)
    }

    @Test func tombstoneSuppressesChildrenAndRunningTimerBlocksCascade() throws {
        let context = try makeSyncRecordContext()
        let project = Project(name: "Timer project", client: "", dailyRate: 0, category: .work)
        context.insert(project)
        let session = Session(project: project, date: .now, startTime: .now, category: .work)
        context.insert(session); try context.save()
        let store = SwiftDataSyncRecordStore(modelContext: context)
        let deletion = SyncRecordChange(key: SyncRecordKey(entity: .project, id: project.id.uuidString), payload: nil)
        #expect(throws: (any Error).self) { try store.apply([deletion]) }
        #expect(try context.fetch(FetchDescriptor<Project>()).count == 1)
        session.status = .completed; try context.save()
        let child = SyncRecordChange(key: SyncRecordKey(entity: .session, id: session.id.uuidString), payload: try SyncPayloadCodec.encode(SessionSyncPayload(session)))
        try store.apply([child, deletion]); try store.saveState(FolderSyncState(), scope: "deleted")
        #expect(try context.fetch(FetchDescriptor<Project>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Session>()).isEmpty)
    }

    @Test func stagedChangesAndCheckpointCommitTogetherAndRollbackOnInvalidHistory() throws {
        let context = try makeSyncRecordContext()
        let store = SwiftDataSyncRecordStore(modelContext: context)
        let project = Project(name: "Staged", client: "", dailyRate: 0, category: .work)
        let change = SyncRecordChange(key: SyncRecordKey(entity: .project, id: project.id.uuidString), payload: try SyncPayloadCodec.encode(ProjectSyncPayload(project)))
        try store.apply([change])
        let observer = ModelContext(syncStoreContainer)
        #expect(try observer.fetch(FetchDescriptor<Project>()).isEmpty)
        try store.saveState(FolderSyncState(), scope: "atomic")
        let committedObserver = ModelContext(syncStoreContainer)
        #expect(try committedObserver.fetch(FetchDescriptor<Project>()).count == 1)
        #expect(try committedObserver.fetch(FetchDescriptor<FolderSyncMetadata>()).count == 1)
        let invalid = SyncOperation(deviceID: UUID(), key: SyncRecordKey(entity: .invoice, id: UUID().uuidString), payload: Data("invalid payload".utf8))
        var state = FolderSyncState()
        try state.ingest([invalid])
        project.name = "Must rollback"
        try store.apply([SyncRecordChange(key: change.key, payload: try SyncPayloadCodec.encode(ProjectSyncPayload(project)))])
        #expect(throws: (any Error).self) { try store.saveState(state, scope: "atomic") }
        #expect(try context.fetch(FetchDescriptor<Project>()).first?.name == "Staged")
        #expect(try store.loadState(scope: "atomic")?.operations.isEmpty == true)
    }

    @Test func incomingRunningSessionIsRejected() throws {
        let context = try makeSyncRecordContext()
        let store = SwiftDataSyncRecordStore(modelContext: context)
        let session = Session(project: nil, date: .now, startTime: .now, category: .work)
        let change = SyncRecordChange(key: SyncRecordKey(entity: .session, id: session.id.uuidString), payload: try SyncPayloadCodec.encode(SessionSyncPayload(session)))
        #expect(throws: (any Error).self) { try store.apply([change]) }
        #expect(try context.fetch(FetchDescriptor<Session>()).isEmpty)
    }

    @Test func historicalInvoiceNumbersRaiseCounterAndCollisionsCanBeRenumbered() throws {
        let context = try makeSyncRecordContext()
        let invoice = Invoice(number: 7, client: "A", periodStart: .now, periodEnd: .now, lineItems: [])
        let duplicate = Invoice(number: 7, client: "B", periodStart: .now, periodEnd: .now, lineItems: [])
        context.insert(invoice); context.insert(duplicate); try context.save()
        let historical = Invoice(number: 100, client: "Deleted", periodStart: .now, periodEnd: .now, lineItems: [])
        var state = FolderSyncState()
        let op = SyncOperation(deviceID: UUID(), key: SyncRecordKey(entity: .invoice, id: historical.id.uuidString), payload: try SyncPayloadCodec.encode(InvoiceSyncPayload(historical)))
        try state.ingest([op, SyncOperation(deviceID: UUID(), key: op.key, parents: [op.id], payload: nil)])
        historical.number = 300
        try state.ingest([SyncOperation(deviceID: UUID(), key: op.key, payload: try SyncPayloadCodec.encode(InvoiceSyncPayload(historical)))])
        #expect(state.conflicts.count == 1)
        let store = SwiftDataSyncRecordStore(modelContext: context)
        try store.saveState(state, scope: "invoices")
        #expect(try context.fetch(FetchDescriptor<AppSettings>()).first?.lastInvoiceNumber == 300)
        #expect(try store.duplicateInvoiceNumbers().first?.invoices.count == 2)
        try store.renumberInvoice(id: duplicate.id)
        #expect(duplicate.number == 301)
        #expect(try store.duplicateInvoiceNumbers().isEmpty)
        #expect(try store.loadState(scope: "invoices")?.operations.count == 3)
    }
}
