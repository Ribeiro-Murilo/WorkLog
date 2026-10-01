import Foundation
import Observation

private enum FolderSyncResolutionError: LocalizedError {
    case unavailableParent

    var errorDescription: String? {
        "Esta versão depende de um projeto excluído ou ainda não disponível. Resolva o conflito do projeto ou restaure-o de um backup antes de recuperar este registro. Você também pode escolher a versão de exclusão."
    }
}

@MainActor
@Observable
final class FolderSyncService {
    private(set) var isEnabled = false
    private(set) var folderPath: String?
    private(set) var status = "Sincronização desativada"
    private(set) var isSynchronizing = false
    private(set) var lastCheckDate: Date?
    private(set) var conflicts: [SyncConflict] = []
    private(set) var invoiceCollisions: [SyncInvoiceCollision] = []
    private(set) var pendingDependencyCount = 0
    private(set) var pendingUploadCount = 0
    private(set) var dataRevision = 0
    private(set) var errorMessage: String?

    @ObservationIgnored private let recordStore: any FolderSyncRecordStoreProtocol
    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private let deviceID: UUID
    @ObservationIgnored private var folderURL: URL?
    @ObservationIgnored private var hasScopedAccess = false
    @ObservationIgnored private var scope = ""
    @ObservationIgnored private var state = FolderSyncState()
    @ObservationIgnored private var fileStore: FolderSyncFileStore?
    @ObservationIgnored private var periodicTask: Task<Void, Never>?
    private static let bookmarkKey = "WorkLog.folderSync.bookmark"
    private static let pathKey = "WorkLog.folderSync.path"
    private static let deviceKey = "WorkLog.folderSync.deviceID"
    private static let lastCheckKey = "WorkLog.folderSync.lastCheck"

    init(recordStore: any FolderSyncRecordStoreProtocol, userDefaults: UserDefaults = .standard) {
        self.recordStore = recordStore
        self.userDefaults = userDefaults
        if let stored = userDefaults.string(forKey: Self.deviceKey), let id = UUID(uuidString: stored) {
            deviceID = id
        } else {
            let id = UUID()
            deviceID = id
            userDefaults.set(id.uuidString, forKey: Self.deviceKey)
        }
        restoreConfiguration()
    }

    private func restoreConfiguration() {
        guard let bookmark = userDefaults.data(forKey: Self.bookmarkKey) else { return }
        isEnabled = true
        folderPath = userDefaults.string(forKey: Self.pathKey)
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
                              relativeTo: nil, bookmarkDataIsStale: &stale)
            let access = url.startAccessingSecurityScopedResource()
            do {
                let restored = try recordStore.loadState(scope: url.standardizedFileURL.path) ?? FolderSyncState()
                folderURL = url
                folderPath = url.path
                scope = url.standardizedFileURL.path
                state = restored
                pendingUploadCount = restored.operations.count
                fileStore = FolderSyncFileStore(folder: url)
                hasScopedAccess = access
                conflicts = state.conflicts
                status = "Aguardando verificação da pasta"
                lastCheckDate = userDefaults.object(forKey: Self.lastCheckKey) as? Date
                if stale { userDefaults.set(try makeBookmark(url), forKey: Self.bookmarkKey) }
            } catch {
                if access { url.stopAccessingSecurityScopedResource() }
                throw error
            }
        } catch {
            errorMessage = error.localizedDescription
            status = "Selecione a pasta novamente"
        }
    }

    private func makeBookmark(_ url: URL) throws -> Data {
        do { return try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) }
        catch { return try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) }
    }

    func chooseFolder(_ url: URL) throws {
        guard !isSynchronizing else { return }
        guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw FolderSyncFileError.unavailableFolder
        }
        let access = url.startAccessingSecurityScopedResource()
        do {
            let newScope = url.standardizedFileURL.path
            let restored = try recordStore.loadState(scope: newScope) ?? FolderSyncState()
            let bookmark = try makeBookmark(url)
            let collisions = try recordStore.duplicateInvoiceNumbers()
            releaseFolderAccess()
            folderURL = url
            hasScopedAccess = access
            folderPath = url.path
            scope = newScope
            state = restored
            fileStore = FolderSyncFileStore(folder: url)
            isEnabled = true
            errorMessage = nil
            conflicts = state.conflicts
            pendingUploadCount = restored.operations.count
            pendingDependencyCount = 0
            invoiceCollisions = collisions
            lastCheckDate = nil
            status = "Aguardando verificação da pasta"
            userDefaults.set(bookmark, forKey: Self.bookmarkKey)
            userDefaults.set(url.path, forKey: Self.pathKey)
            userDefaults.removeObject(forKey: Self.lastCheckKey)
            if periodicTask != nil { Task { await synchronize() } }
        } catch {
            if access { url.stopAccessingSecurityScopedResource() }
            throw error
        }
    }

    func disconnect() {
        guard !isSynchronizing else { return }
        releaseFolderAccess()
        folderURL = nil
        folderPath = nil
        fileStore = nil
        isEnabled = false
        state = FolderSyncState()
        scope = ""
        conflicts = []
        invoiceCollisions = []
        errorMessage = nil
        pendingUploadCount = 0
        pendingDependencyCount = 0
        lastCheckDate = nil
        status = "Sincronização desativada"
        userDefaults.removeObject(forKey: Self.bookmarkKey)
        userDefaults.removeObject(forKey: Self.pathKey)
        userDefaults.removeObject(forKey: Self.lastCheckKey)
    }

    private func releaseFolderAccess() {
        if hasScopedAccess { folderURL?.stopAccessingSecurityScopedResource() }
        hasScopedAccess = false
    }

    func start() {
        guard periodicTask == nil else { return }
        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.synchronize()
                do { try await Task.sleep(for: .seconds(15)) }
                catch { break }
            }
        }
    }

    func stop() {
        periodicTask?.cancel()
        periodicTask = nil
    }

    func synchronize() async {
        guard isEnabled, let fileStore, !isSynchronizing else { return }
        isSynchronizing = true
        errorMessage = nil
        status = "Verificando a pasta…"
        defer { isSynchronizing = false }
        do {
            var working = state
            let local = try working.captureLocal(recordStore.snapshot(), deviceID: deviceID, now: .now)
            if !local.isEmpty {
                try recordStore.saveState(working, scope: scope)
                state = working
            }
            pendingUploadCount = max(pendingUploadCount, local.count)
            let batch = try await fileStore.readOperations()
            var published = Set(batch.operations.map(\.id))
            let outbox = working.operations.filter { !published.contains($0.id) }
            pendingUploadCount = outbox.count
            for operation in outbox {
                try await fileStore.publish(operation)
                published.insert(operation.id)
                pendingUploadCount -= 1
            }

            // UI edits may have occurred while file I/O suspended this actor. Capture
            // them before ingesting remote parents, with no suspension before save.
            let before = try recordStore.snapshot()
            let lateLocal = try working.captureLocal(before, deviceID: deviceID, now: .now)
            if !lateLocal.isEmpty {
                try recordStore.saveState(working, scope: scope)
                state = working
            }
            pendingUploadCount = working.operations.filter { !published.contains($0.id) }.count
            try working.ingest(batch.operations)
            let projection = try applicableProjection(working, snapshot: before)
            try recordStore.apply(projection.changes)
            let after = try recordStore.snapshot()
            working.baseline = after
            try recordStore.saveState(working, scope: scope)
            state = working
            conflicts = working.conflicts
            pendingDependencyCount = working.pendingDependencyCount + batch.unavailableFiles + projection.deferred
            invoiceCollisions = try recordStore.duplicateInvoiceNumbers()
            if before != after { dataRevision += 1 }
            lastCheckDate = .now
            userDefaults.set(lastCheckDate, forKey: Self.lastCheckKey)
            updateStatus()
        } catch {
            recordStore.rollback()
            conflicts = state.conflicts
            errorMessage = error.localizedDescription
            status = "Não foi possível concluir a verificação"
        }
    }

    /// A conflicted or not-yet-delivered project may be absent on a new Mac.
    /// Keep those child versions in the journal until the parent is available.
    private func applicableProjection(_ working: FolderSyncState, snapshot: [SyncRecordKey: Data]) throws
        -> (changes: [SyncRecordChange], deferred: Int) {
        let changes = working.resolvedChanges()
        let deleted = Set(changes.filter { $0.key.entity == .project && $0.payload == nil }.map { $0.key.id })
        var available = Set(snapshot.keys.filter { $0.entity == .project }.map(\.id))
        available.formUnion(changes.filter { $0.key.entity == .project && $0.payload != nil }.map { $0.key.id })
        available.subtract(deleted)
        var applicable: [SyncRecordChange] = []
        var deferred = 0
        for change in changes {
            var parentID: UUID?
            if let data = change.payload {
                if change.key.entity == .session {
                    parentID = try SyncPayloadCodec.decode(SessionSyncPayload.self, from: data).projectId
                } else if change.key.entity == .comment {
                    parentID = try SyncPayloadCodec.decode(CommentSyncPayload.self, from: data).projectId
                }
            }
            if let parentID, !available.contains(parentID.uuidString), !deleted.contains(parentID.uuidString) {
                deferred += 1
            } else {
                applicable.append(change)
            }
        }
        return (applicable, deferred)
    }

    private func updateStatus() {
        if !conflicts.isEmpty || !invoiceCollisions.isEmpty { status = "Há alterações para revisar" }
        else if pendingDependencyCount > 0 { status = "Aguardando arquivos relacionados" }
        else if pendingUploadCount > 0 { status = "Há alterações locais aguardando gravação na pasta" }
        else { status = "Pasta verificada neste Mac" }
    }

    func keepLocal(_ conflict: SyncConflict) async {
        do { await resolve(conflict, using: try recordStore.snapshot()[conflict.key]) }
        catch { errorMessage = error.localizedDescription }
    }

    func resolve(_ conflict: SyncConflict, using payload: Data?) async {
        guard isEnabled, !isSynchronizing else { return }
        do {
            var working = state
            // Reconcile local edits before recording the explicit resolution.
            _ = try working.captureLocal(recordStore.snapshot(), deviceID: deviceID, now: .now)
            _ = try working.resolve(key: conflict.key, payload: payload, deviceID: deviceID, now: .now)
            let before = try recordStore.snapshot()
            let projection = try applicableProjection(working, snapshot: before)
            try recordStore.apply(projection.changes)
            let after = try recordStore.snapshot()
            if payload != nil, [.session, .comment].contains(conflict.key.entity), after[conflict.key] != payload {
                throw FolderSyncResolutionError.unavailableParent
            }
            working.baseline = after
            try recordStore.saveState(working, scope: scope)
            state = working
            conflicts = working.conflicts
            if before != after { dataRevision += 1 }
            await synchronize()
        } catch {
            recordStore.rollback()
            errorMessage = error.localizedDescription
            status = "Não foi possível resolver o conflito"
        }
    }

    func renumberInvoice(id: UUID) async {
        guard isEnabled, !isSynchronizing else { return }
        do {
            try recordStore.renumberInvoice(id: id)
            dataRevision += 1
            await synchronize()
        } catch {
            recordStore.rollback()
            errorMessage = error.localizedDescription
        }
    }
}
