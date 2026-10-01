import Foundation
import SwiftData
import Testing
@testable import WorkLog

@Suite(.serialized) @MainActor
struct FolderSyncServiceTests {
    private let key = SyncRecordKey(entity: .project, id: UUID().uuidString)

    @Test func deferredRelationshipCannotBeImplicitlyOverwrittenOrFalselyResolved() async throws {
        let fixture = try SyncServiceFixture()
        defer { fixture.cleanUp() }
        let context = try emptyConflictContext()
        let store = SwiftDataSyncRecordStore(modelContext: context)
        let service = FolderSyncService(recordStore: store, userDefaults: fixture.makeDefaults())
        let originalProject = Project(name: "Available", client: "Client", dailyRate: 800, category: .work)
        context.insert(originalProject)
        let session = Session(project: originalProject, date: .now, startTime: .now.addingTimeInterval(-60), endTime: .now,
                              durationSeconds: 60, note: "base", category: .work, status: .completed)
        context.insert(session)
        try context.save()
        let sessionKey = SyncRecordKey(entity: .session, id: session.id.uuidString)
        try service.chooseFolder(fixture.folder)
        await service.synchronize()
        let state = try #require(try store.loadState(scope: fixture.folder.standardizedFileURL.path))
        let ancestor = try #require(state.operations.first { $0.key == sessionKey })
        let missingProject = Project(name: "Not delivered yet", client: "Other", dailyRate: 400, category: .work)
        let remoteSession = Session(project: missingProject, date: session.date, startTime: session.startTime, endTime: session.endTime,
                                    durationSeconds: session.durationSeconds, note: "remote", category: session.category, status: .completed)
        remoteSession.id = session.id
        let remote = SyncOperation(deviceID: UUID(), key: sessionKey, parents: [ancestor.id],
                                   payload: try SyncPayloadCodec.encode(SessionSyncPayload(remoteSession)))
        let files = FolderSyncFileStore(folder: fixture.folder)
        try await files.publish(remote)
        await service.synchronize()
        #expect(service.errorMessage == nil)
        #expect(service.pendingDependencyCount > 0)
        #expect(session.project?.id == originalProject.id)
        session.note = "new local edit"
        try context.save()
        await service.synchronize()
        let conflict = try #require(service.conflicts.first { $0.key == sessionKey })
        await service.resolve(conflict, using: remote.payload)
        #expect(service.errorMessage != nil)
        #expect(service.conflicts.count == 1)
        #expect(session.project?.id == originalProject.id)
        #expect(session.note == "new local edit")
        let parent = SyncOperation(deviceID: remote.deviceID, key: SyncRecordKey(entity: .project, id: missingProject.id.uuidString),
                                   payload: try SyncPayloadCodec.encode(ProjectSyncPayload(missingProject)))
        try await files.publish(parent)
        await service.synchronize()
        if let retry = service.conflicts.first { await service.resolve(retry, using: remote.payload) }
        #expect(service.errorMessage == nil)
        #expect(service.conflicts.isEmpty)
        #expect(session.project?.id == missingProject.id)
        #expect(session.note == "remote")
    }

    @Test func missingAncestorCanArriveAfterALocalEditWithoutBlockingPolling() async throws {
        let fixture = try SyncServiceFixture()
        defer { fixture.cleanUp() }
        let first = fixture.makeService()
        first.store.records[key] = Data("base".utf8)
        try first.service.chooseFolder(fixture.folder)
        await first.service.synchronize()
        let base = try #require(first.store.states.values.first?.operations.first)
        let parent = SyncOperation(deviceID: UUID(), key: key, parents: [base.id], payload: Data("remote intermediate".utf8))
        let child = SyncOperation(deviceID: parent.deviceID, key: key, parents: [parent.id], payload: Data("remote latest".utf8))
        let files = FolderSyncFileStore(folder: fixture.folder)
        try await files.publish(child)
        await first.service.synchronize()
        #expect(first.service.pendingDependencyCount > 0)
        first.store.records[key] = Data("local offline edit".utf8)
        try await files.publish(parent)
        await first.service.synchronize()
        #expect(first.service.errorMessage == nil)
        #expect(first.service.pendingDependencyCount == 0)
        #expect(first.service.conflicts.count == 1)
        #expect(first.store.records[key] == Data("local offline edit".utf8))
    }

    @Test func newMacCanResolveConflictedParentBeforeImportingItsChildren() async throws {
        let fixture = try SyncServiceFixture()
        defer { fixture.cleanUp() }
        let context = try emptyConflictContext()
        let store = SwiftDataSyncRecordStore(modelContext: context)
        let service = FolderSyncService(recordStore: store, userDefaults: fixture.makeDefaults())
        let project = Project(name: "Base", client: "Client", dailyRate: 800, category: .work)
        let projectKey = SyncRecordKey(entity: .project, id: project.id.uuidString)
        let root = SyncOperation(deviceID: UUID(), key: projectKey, payload: try SyncPayloadCodec.encode(ProjectSyncPayload(project)))
        project.name = "First edit"
        let first = SyncOperation(deviceID: UUID(), key: projectKey, parents: [root.id], payload: try SyncPayloadCodec.encode(ProjectSyncPayload(project)))
        project.name = "Second edit"
        let second = SyncOperation(deviceID: UUID(), key: projectKey, parents: [root.id], payload: try SyncPayloadCodec.encode(ProjectSyncPayload(project)))
        let session = Session(project: project, date: .now, startTime: .now.addingTimeInterval(-60), endTime: .now,
                              durationSeconds: 60, note: "Waiting for parent", category: .work, status: .completed)
        let child = SyncOperation(deviceID: root.deviceID, key: SyncRecordKey(entity: .session, id: session.id.uuidString),
                                  payload: try SyncPayloadCodec.encode(SessionSyncPayload(session)))
        let files = FolderSyncFileStore(folder: fixture.folder)
        for op in [root, first, second, child] { try await files.publish(op) }
        try service.chooseFolder(fixture.folder)
        await service.synchronize()
        #expect(service.errorMessage == nil)
        #expect(service.conflicts.count == 1)
        #expect(service.pendingDependencyCount > 0)
        #expect(try store.loadState(scope: fixture.folder.standardizedFileURL.path)?.operations.count == 4)
        if let conflict = service.conflicts.first {
            await service.resolve(conflict, using: first.payload)
            #expect(service.errorMessage == nil)
            #expect(service.conflicts.isEmpty)
            #expect(try context.fetch(FetchDescriptor<Project>()).first?.name == "First edit")
            #expect(try context.fetch(FetchDescriptor<Session>()).first?.id == session.id)
        }
    }

    @Test func choosingChildOfDeletedProjectKeepsConflictAndExplainsRecovery() async throws {
        let fixture = try SyncServiceFixture()
        defer { fixture.cleanUp() }
        let context = try emptyConflictContext()
        let service = FolderSyncService(recordStore: SwiftDataSyncRecordStore(modelContext: context), userDefaults: fixture.makeDefaults())
        let project = Project(name: "Deleted", client: "Client", dailyRate: 800, category: .work)
        let projectKey = SyncRecordKey(entity: .project, id: project.id.uuidString)
        let root = SyncOperation(deviceID: UUID(), key: projectKey, payload: try SyncPayloadCodec.encode(ProjectSyncPayload(project)))
        let deleted = SyncOperation(deviceID: root.deviceID, key: projectKey, parents: [root.id], payload: nil)
        let session = Session(project: project, date: .now, startTime: .now.addingTimeInterval(-60), endTime: .now,
                              durationSeconds: 60, category: .work, status: .completed)
        let sessionKey = SyncRecordKey(entity: .session, id: session.id.uuidString)
        let child = SyncOperation(deviceID: root.deviceID, key: sessionKey, payload: try SyncPayloadCodec.encode(SessionSyncPayload(session)))
        let childDelete = SyncOperation(deviceID: root.deviceID, key: sessionKey, parents: [child.id], payload: nil)
        session.note = "Offline edit preserved"
        let childEdit = SyncOperation(deviceID: UUID(), key: sessionKey, parents: [child.id], payload: try SyncPayloadCodec.encode(SessionSyncPayload(session)))
        let files = FolderSyncFileStore(folder: fixture.folder)
        for op in [root, deleted, child, childDelete, childEdit] { try await files.publish(op) }
        try service.chooseFolder(fixture.folder)
        await service.synchronize()
        let conflict = try #require(service.conflicts.first)
        await service.resolve(conflict, using: childEdit.payload)
        #expect(service.errorMessage != nil)
        #expect(service.conflicts.count == 1)
        #expect(try context.fetch(FetchDescriptor<Session>()).isEmpty)
    }

    @Test func realSwiftDataBanksExchangeModelsEditsAndCascadeDeletes() async throws {
        let fixture = try SyncServiceFixture()
        defer { fixture.cleanUp() }
        let source = ModelContext(serviceTestContainers.0)
        let destination = ModelContext(serviceTestContainers.1)
        source.autosaveEnabled = false
        destination.autosaveEnabled = false
        let project = Project(name: "Shared", client: "Client", dailyRate: 800, category: .work)
        let projectID = project.id
        source.insert(project)
        let session = Session(project: project, date: .now, startTime: .now.addingTimeInterval(-60), endTime: .now,
                              durationSeconds: 60, note: "Preserved", category: .work, status: .completed)
        let sessionID = session.id
        source.insert(session)
        let issuer = AppSettings(invoiceIssuerName: "Issuer")
        source.insert(issuer)
        let localSettings = AppSettings(launchAtLogin: false, idleTimeoutMinutes: 30, displayMode: .notch)
        destination.insert(localSettings)
        try source.save()
        try destination.save()
        let first = FolderSyncService(recordStore: SwiftDataSyncRecordStore(modelContext: source), userDefaults: fixture.makeDefaults())
        let second = FolderSyncService(recordStore: SwiftDataSyncRecordStore(modelContext: destination), userDefaults: fixture.makeDefaults())
        try first.chooseFolder(fixture.folder)
        try second.chooseFolder(fixture.folder)
        await first.synchronize()
        await second.synchronize()
        #expect(first.errorMessage == nil)
        #expect(second.errorMessage == nil)
        let received = try #require(destination.fetch(FetchDescriptor<Project>()).first)
        #expect(received.id == projectID)
        #expect(try destination.fetch(FetchDescriptor<Session>()).first?.id == sessionID)
        #expect(localSettings.invoiceIssuerName == "Issuer")
        #expect(!localSettings.launchAtLogin)
        #expect(localSettings.displayMode == .notch)
        received.name = "Edited on second Mac"
        try destination.save()
        await second.synchronize()
        await first.synchronize()
        #expect(project.name == "Edited on second Mac")
        #expect(first.conflicts.isEmpty)
        destination.delete(received)
        try destination.save()
        await second.synchronize()
        await first.synchronize()
        #expect(first.errorMessage == nil)
        #expect(try source.fetch(FetchDescriptor<Project>()).isEmpty)
        #expect(try source.fetch(FetchDescriptor<Session>()).isEmpty)
    }

    @Test func twoMacsExchangeChangesAndDeletionsWithoutDuplicateRecords() async throws {
        let fixture = try SyncServiceFixture()
        defer { fixture.cleanUp() }
        let first = fixture.makeService()
        let second = fixture.makeService()
        first.store.records[key] = Data("original".utf8)
        try first.service.chooseFolder(fixture.folder)
        try second.service.chooseFolder(fixture.folder)

        await first.service.synchronize()
        await second.service.synchronize()
        #expect(second.store.records[key] == Data("original".utf8))
        await second.service.synchronize()
        #expect(second.store.records.count == 1)

        second.store.records[key] = Data("edited".utf8)
        await second.service.synchronize()
        await first.service.synchronize()
        #expect(first.store.records[key] == Data("edited".utf8))

        second.store.records.removeValue(forKey: key)
        await second.service.synchronize()
        await first.service.synchronize()
        #expect(first.store.records[key] == nil)
        #expect(first.service.errorMessage == nil)
    }

    @Test func concurrentOfflineEditsArePreservedUntilExplicitResolution() async throws {
        let fixture = try SyncServiceFixture()
        defer { fixture.cleanUp() }
        let first = fixture.makeService()
        let second = fixture.makeService()
        first.store.records[key] = Data("base".utf8)
        try first.service.chooseFolder(fixture.folder)
        try second.service.chooseFolder(fixture.folder)
        await first.service.synchronize()
        await second.service.synchronize()

        first.store.records[key] = Data("first edit".utf8)
        second.store.records[key] = Data("second edit".utf8)
        await first.service.synchronize()
        await second.service.synchronize()
        await first.service.synchronize()
        #expect(first.service.conflicts.count == 1)
        #expect(second.service.conflicts.count == 1)
        #expect(first.store.records[key] == Data("first edit".utf8))
        #expect(second.store.records[key] == Data("second edit".utf8))

        let conflict = try #require(first.service.conflicts.first)
        await first.service.keepLocal(conflict)
        await second.service.synchronize()
        #expect(second.store.records[key] == Data("first edit".utf8))
        #expect(second.service.conflicts.isEmpty)
    }

    @Test func folderFailureRetainsOutboxAndRetriesAfterRestart() async throws {
        let fixture = try SyncServiceFixture()
        defer { fixture.cleanUp() }
        let first = fixture.makeService()
        first.store.records[key] = Data("offline".utf8)
        try first.service.chooseFolder(fixture.folder)
        try FileManager.default.removeItem(at: fixture.folder)
        await first.service.synchronize()
        #expect(first.service.errorMessage != nil)
        #expect(first.store.records[key] == Data("offline".utf8))
        #expect(first.store.states.values.first?.operations.count == 1)

        try FileManager.default.createDirectory(at: fixture.folder, withIntermediateDirectories: true)
        let restarted = FolderSyncService(recordStore: first.store, userDefaults: first.defaults)
        await restarted.synchronize()
        let second = fixture.makeService()
        try second.service.chooseFolder(fixture.folder)
        await second.service.synchronize()
        #expect(second.store.records[key] == Data("offline".utf8))
        #expect(restarted.errorMessage == nil)
    }

    @Test func futureFileDoesNotOverwriteLocalRecords() async throws {
        let fixture = try SyncServiceFixture()
        defer { fixture.cleanUp() }
        let first = fixture.makeService()
        first.store.records[key] = Data("kept".utf8)
        try first.service.chooseFolder(fixture.folder)
        await first.service.synchronize()
        let operation = SyncOperation(formatVersion: 99, deviceID: UUID(), key: key, payload: Data("future".utf8))
        let file = fixture.folder.appendingPathComponent("WorkLog Sync/Operations/\(operation.id.uuidString).json")
        try JSONEncoder().encode(operation).write(to: file)
        await first.service.synchronize()
        #expect(first.service.errorMessage != nil)
        #expect(first.store.records[key] == Data("kept".utf8))
    }

    @Test func disconnectAndChangingFolderPreserveDataAndPreviousFiles() async throws {
        let fixture = try SyncServiceFixture()
        defer { fixture.cleanUp() }
        let first = fixture.makeService()
        first.store.records[key] = Data("kept".utf8)
        try first.service.chooseFolder(fixture.folder)
        await first.service.synchronize()
        let files = try FileManager.default.contentsOfDirectory(atPath: fixture.folder.appendingPathComponent("WorkLog Sync/Operations").path)
        first.service.disconnect()
        #expect(!first.service.isEnabled)
        #expect(first.store.records[key] != nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.folder.appendingPathComponent("WorkLog Sync/Operations").path) == files)
        let other = fixture.folder.appendingPathComponent("Another")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try first.service.chooseFolder(other)
        await first.service.synchronize()
        #expect(first.service.errorMessage == nil)
        #expect(first.store.states.count == 2)
        #expect(first.store.records[key] != nil)
    }
}

@MainActor
private let conflictTestContainer: ModelContainer = {
    let schema = PersistenceController.schema()
    return try! ModelContainer(for: schema, configurations: [ModelConfiguration("sync-conflict-store", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
}()

@MainActor
private func emptyConflictContext() throws -> ModelContext {
    let context = ModelContext(conflictTestContainer)
    context.autosaveEnabled = false
    try context.delete(model: Session.self)
    try context.delete(model: WorkLog.Comment.self)
    try context.delete(model: Project.self)
    try context.delete(model: Invoice.self)
    try context.delete(model: ReportPreset.self)
    try context.delete(model: AppSettings.self)
    try context.delete(model: FolderSyncMetadata.self)
    try context.save()
    return context
}

@MainActor
private final class MemorySyncStore: FolderSyncRecordStoreProtocol {
    var records: [SyncRecordKey: Data] = [:]
    var states: [String: FolderSyncState] = [:]
    private var committed: [SyncRecordKey: Data] = [:]

    func snapshot() throws -> [SyncRecordKey: Data] { records }
    func apply(_ changes: [SyncRecordChange]) throws {
        for change in changes { records[change.key] = change.payload }
    }
    func loadState(scope: String) throws -> FolderSyncState? { states[scope] }
    func saveState(_ state: FolderSyncState, scope: String) throws {
        states[scope] = state
        committed = records
    }
    func rollback() { records = committed }
    func duplicateInvoiceNumbers() throws -> [SyncInvoiceCollision] { [] }
    func renumberInvoice(id: UUID) throws {}
}

@MainActor
private struct SyncServiceFixture {
    let folder: URL
    private let defaultsNames: NSMutableArray = []

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("WorkLog-Sync-Tests-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    func makeService() -> (service: FolderSyncService, store: MemorySyncStore, defaults: UserDefaults) {
        let defaults = makeDefaults()
        let store = MemorySyncStore()
        return (FolderSyncService(recordStore: store, userDefaults: defaults), store, defaults)
    }
    func makeDefaults() -> UserDefaults {
        let name = "WorkLog.FolderSync.Tests.\(UUID())"
        defaultsNames.add(name)
        let defaults = UserDefaults(suiteName: name)!
        return defaults
    }
    func cleanUp() {
        try? FileManager.default.removeItem(at: folder)
        for name in defaultsNames { UserDefaults.standard.removePersistentDomain(forName: name as! String) }
    }
}

@MainActor
private let serviceTestContainers: (ModelContainer, ModelContainer) = {
    let schema = PersistenceController.schema()
    return (
        try! ModelContainer(for: schema, configurations: [ModelConfiguration("sync-service-first", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)]),
        try! ModelContainer(for: schema, configurations: [ModelConfiguration("sync-service-second", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
    )
}()
