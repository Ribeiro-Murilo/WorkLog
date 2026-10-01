import Foundation
import Testing
@testable import WorkLog

struct SyncJournalTests {
    private let device = UUID()
    private let key = SyncRecordKey(entity: .project, id: UUID().uuidString)
    private let now = Date(timeIntervalSince1970: 100)
    private func bytes(_ value: String) -> Data { Data(value.utf8) }
    private func operation(_ value: String?, parents: [UUID] = []) -> SyncOperation {
        SyncOperation(deviceID: device, key: key, parents: parents, payload: value.map(bytes), timestamp: now)
    }

    @Test func causalEditReplacesAncestorRegardlessOfArrivalOrder() throws {
        let first = operation("first")
        let next = operation("next", parents: [first.id])
        var state = FolderSyncState()
        try state.ingest([next, first])
        #expect(state.conflicts.isEmpty)
        #expect(state.resolvedChanges().map(\.payload) == [bytes("next")])
    }

    @Test func concurrentEditAndDeleteRemainAConflictUntilExplicitResolution() throws {
        let first = operation("first")
        let edit = operation("edit", parents: [first.id])
        let deletion = operation(nil, parents: [first.id])
        var state = FolderSyncState()
        try state.ingest([edit, first, deletion])
        #expect(state.conflicts.count == 1)
        #expect(state.resolvedChanges().isEmpty)
        let resolution = try state.resolve(key: key, payload: nil, deviceID: device, now: now)
        #expect(Set(resolution.parents) == Set([edit.id, deletion.id]))
        #expect(state.conflicts.isEmpty)
        #expect(state.resolvedChanges().count == 1)
        #expect(state.resolvedChanges().first?.payload == nil)
    }

    @Test func identicalConcurrentContentsConvergeAndNextEditParentsBoth() throws {
        let a = operation("same")
        let b = operation("same")
        var state = FolderSyncState()
        try state.ingest([b, a])
        state.baseline[key] = bytes("same")
        #expect(state.conflicts.isEmpty)
        let local = try state.captureLocal([key: bytes("changed")], deviceID: device, now: now)
        #expect(Set(local[0].parents) == Set([a.id, b.id]))
    }

    @Test func replayIsIdempotentAndChangingAnOperationIDFailsAtomically() throws {
        let first = operation("first")
        var state = FolderSyncState()
        try state.ingest([first, first])
        #expect(state.operations.count == 1)
        var tampered = first
        tampered.payload = bytes("tampered")
        #expect(throws: SyncProtocolError.self) { try state.ingest([operation("other"), tampered]) }
        #expect(state.operations == [first])
    }

    @Test func missingGrandparentBlocksProjectionAndResolution() throws {
        let missing = UUID()
        let first = operation("first", parents: [missing])
        let next = operation("next", parents: [first.id])
        var state = FolderSyncState()
        try state.ingest([next, first])
        #expect(state.pendingDependencyCount == 2)
        #expect(state.resolvedChanges().isEmpty)
        #expect(throws: SyncProtocolError.self) { try state.resolve(key: key, payload: bytes("local"), deviceID: device, now: now) }
        let ancestor = SyncOperation(id: missing, deviceID: device, key: key, payload: bytes("old"), timestamp: now)
        try state.ingest([ancestor])
        #expect(state.pendingDependencyCount == 0)
        #expect(state.resolvedChanges().first?.payload == bytes("next"))
    }

    @Test func checkpointedMissingAncestorPreservesLocalEditAndEventuallyConflicts() throws {
        var state = FolderSyncState()
        let initial = try state.captureLocal([key: bytes("initial")], deviceID: device, now: now)[0]
        let missing = operation("intermediate", parents: [initial.id])
        // The known initial version is removed from heads even though the remote
        // descendant cannot be projected until its other parent arrives.
        let remote = operation("remote", parents: [initial.id, missing.id])
        try state.ingest([remote])
        state = try JSONDecoder().decode(FolderSyncState.self, from: JSONEncoder().encode(state))
        let local = try state.captureLocal([key: bytes("local")], deviceID: device, now: now)[0]
        #expect(local.parents == [initial.id])
        #expect(state.resolvedChanges().isEmpty)
        #expect(state.operations.contains(remote))
        #expect(throws: SyncProtocolError.self) { try state.resolve(key: key, payload: bytes("local"), deviceID: device, now: now) }
        try state.ingest([missing])
        #expect(state.pendingDependencyCount == 0)
        #expect(Set(state.conflicts[0].versions.map(\.id)) == Set([local.id, remote.id]))
        let resolution = try state.resolve(key: key, payload: bytes("chosen"), deviceID: device, now: now)
        #expect(Set(resolution.parents) == Set([local.id, remote.id]))
        #expect(state.resolvedChanges().first?.payload == bytes("chosen"))
    }

    @Test func missingRemoteRecordAndNewLocalRecordStartIndependentBranches() throws {
        var state = FolderSyncState()
        let ancestor = operation("ancestor")
        let remote = operation("remote", parents: [ancestor.id])
        try state.ingest([remote])
        let local = try state.captureLocal([key: bytes("local")], deviceID: device, now: now)[0]
        #expect(local.parents.isEmpty)
        #expect(state.pendingDependencyCount == 1)
        #expect(state.resolvedChanges().isEmpty)
        try state.ingest([ancestor])
        #expect(Set(state.conflicts[0].versions.map(\.id)) == Set([local.id, remote.id]))
    }

    @Test func incompleteCaptureUsesLatestCompleteBaselineAndPreservesSubsequentDeletion() throws {
        var state = FolderSyncState()
        let first = try state.captureLocal([key: bytes("same")], deviceID: device, now: now)[0]
        _ = try state.captureLocal([key: bytes("different")], deviceID: device, now: now)
        let latest = try state.captureLocal([key: bytes("same")], deviceID: device, now: now)[0]
        let missing = operation("intermediate", parents: [latest.id])
        let remote = operation("remote", parents: [latest.id, missing.id])
        try state.ingest([remote])
        let local = try state.captureLocal([key: bytes("local")], deviceID: device, now: now)[0]
        #expect(local.parents == [latest.id])
        #expect(!local.parents.contains(first.id))
        let deletion = try state.captureLocal([:], deviceID: device, now: now)[0]
        #expect(deletion.parents == [local.id])
        #expect(deletion.payload == nil)
        try state.ingest([missing])
        #expect(Set(state.conflicts[0].versions.map(\.id)) == Set([deletion.id, remote.id]))
        #expect(state.resolvedChanges().isEmpty)
    }

    @Test func localChangesAreCapturedBeforeIngestingRemoteEdits() throws {
        var state = FolderSyncState()
        let initial = try state.captureLocal([key: bytes("initial")], deviceID: device, now: now)[0]
        let remote = operation("remote", parents: [initial.id])
        let local = try state.captureLocal([key: bytes("local")], deviceID: device, now: now)[0]
        try state.ingest([remote])
        #expect(Set(state.conflicts[0].versions.map(\.id)) == Set([local.id, remote.id]))
        #expect(state.baseline[key] == bytes("local"))
        #expect(try state.captureLocal([key: bytes("local")], deviceID: device, now: now).isEmpty)
        let further = try state.captureLocal([key: bytes("further")], deviceID: device, now: now)[0]
        #expect(further.parents == [local.id])
        #expect(state.conflicts.count == 1)
    }

    @Test func localBaselineHiddenBehindCompleteRemoteConflictCanStillBeEdited() throws {
        var state = FolderSyncState()
        let initial = try state.captureLocal([key: bytes("initial")], deviceID: device, now: now)[0]
        let remoteA = operation("remote A", parents: [initial.id])
        let remoteB = operation("remote B", parents: [initial.id])
        try state.ingest([remoteA, remoteB])
        #expect(state.conflicts.count == 1)
        #expect(state.baseline[key] == bytes("initial"))
        let local = try state.captureLocal([key: bytes("local")], deviceID: device, now: now)[0]
        #expect(local.parents == [initial.id])
        #expect(Set(state.conflicts[0].versions.map(\.id)) == Set([remoteA.id, remoteB.id, local.id]))
        #expect(state.resolvedChanges().isEmpty)
        let chosen = try state.resolve(key: key, payload: bytes("local"), deviceID: device, now: now)
        #expect(Set(chosen.parents) == Set([remoteA.id, remoteB.id, local.id]))
        #expect(state.conflicts.isEmpty)
    }

    @Test func deferredCompleteRemoteVersionCannotBecomeParentOfUnseenLocalEdit() throws {
        var state = FolderSyncState()
        let initial = try state.captureLocal([key: bytes("initial")], deviceID: device, now: now)[0]
        let remote = operation("remote", parents: [initial.id])
        try state.ingest([remote])
        // Projection was deferred by the record store, so the database still has
        // the initial payload even though the complete remote version is known.
        #expect(state.baseline[key] == bytes("initial"))
        let local = try state.captureLocal([key: bytes("local")], deviceID: device, now: now)[0]
        #expect(local.parents == [initial.id])
        let conflict = try #require(state.conflicts.first)
        #expect(Set(conflict.versions.map(\.id)) == Set([remote.id, local.id]))
        #expect(state.resolvedChanges().isEmpty)
    }

    @Test func unappliedRemoteRecordAndNewLocalRecordStartIndependentBranches() throws {
        var state = FolderSyncState()
        let remote = operation("remote")
        try state.ingest([remote])
        let local = try state.captureLocal([key: bytes("local")], deviceID: device, now: now)[0]
        #expect(local.parents.isEmpty)
        let conflict = try #require(state.conflicts.first)
        #expect(Set(conflict.versions.map(\.id)) == Set([remote.id, local.id]))
    }

    @Test func localRecreationContinuesTombstoneHiddenBehindRemoteConflict() throws {
        var state = FolderSyncState()
        _ = try state.captureLocal([key: bytes("initial")], deviceID: device, now: now)
        let deletion = try state.captureLocal([:], deviceID: device, now: now)[0]
        let remoteA = operation("remote A", parents: [deletion.id])
        let remoteB = operation("remote B", parents: [deletion.id])
        try state.ingest([remoteA, remoteB])
        let local = try state.captureLocal([key: bytes("local")], deviceID: device, now: now)[0]
        #expect(local.parents == [deletion.id])
        #expect(Set(state.conflicts[0].versions.map(\.id)) == Set([remoteA.id, remoteB.id, local.id]))
    }

    @Test func deletingLocalRecordsProducesPersistentTombstones() throws {
        var state = FolderSyncState()
        let initial = try state.captureLocal([key: bytes("initial")], deviceID: device, now: now)[0]
        let deletion = try state.captureLocal([:], deviceID: device, now: now)[0]
        #expect(deletion.payload == nil)
        #expect(deletion.parents == [initial.id])
        #expect(state.baseline.isEmpty)
        #expect(try state.captureLocal([:], deviceID: device, now: now).isEmpty)
        #expect(state.operations.count == 2)
    }

    @Test func rejectsFutureVersionSelfCycleCrossRecordAndGraphCycle() throws {
        var future = operation("future")
        future.formatVersion = 2
        var selfParent = operation("self")
        selfParent.parents = [selfParent.id]
        let aID = UUID(), bID = UUID()
        let a = SyncOperation(id: aID, deviceID: device, key: key, parents: [bID], payload: bytes("a"))
        let b = SyncOperation(id: bID, deviceID: device, key: key, parents: [aID], payload: bytes("b"))
        let other = SyncOperation(deviceID: device, key: SyncRecordKey(entity: .invoice, id: "other"), payload: bytes("other"))
        let wrongParent = operation("wrong", parents: [other.id])
        for batch in [[future], [selfParent], [a, b], [other, wrongParent]] {
            var state = FolderSyncState()
            #expect(throws: SyncProtocolError.self) { try state.ingest(batch) }
            #expect(state.operations.isEmpty)
        }
    }

    @Test func lateInvalidParentDoesNotMutateWaitingJournal() throws {
        let ancestorID = UUID()
        let child = operation("child", parents: [ancestorID])
        let wrong = SyncOperation(id: ancestorID, deviceID: device, key: SyncRecordKey(entity: .invoice, id: "other"), payload: bytes("wrong"))
        var state = FolderSyncState()
        try state.ingest([child])
        #expect(throws: SyncProtocolError.self) { try state.ingest([wrong]) }
        #expect(state.operations == [child])
        #expect(state.pendingDependencyCount == 1)
    }

    @Test func stateRoundTripsBaselineAndConflictHistory() throws {
        var state = FolderSyncState()
        _ = try state.captureLocal([key: bytes("local")], deviceID: device, now: now)
        try state.ingest([operation("remote")])
        let restored = try JSONDecoder().decode(FolderSyncState.self, from: JSONEncoder().encode(state))
        #expect(restored.baseline == state.baseline)
        #expect(restored.operations == state.operations)
        #expect(restored.conflicts.count == 1)
    }

    @Test func captureIsAtomicWhenIncompleteRecordHasNoCompleteBaselineVersion() throws {
        let blocked = SyncRecordKey(entity: .comment, id: "blocked")
        var state = FolderSyncState()
        state.baseline[blocked] = bytes("old")
        try state.ingest([SyncOperation(deviceID: device, key: blocked, parents: [UUID()], payload: bytes("pending"))])
        #expect(throws: SyncProtocolError.self) {
            try state.captureLocal([key: bytes("valid"), blocked: bytes("local")], deviceID: device, now: now)
        }
        #expect(state.operations.count == 1)
        #expect(state.baseline == [blocked: bytes("old")])
    }
}
