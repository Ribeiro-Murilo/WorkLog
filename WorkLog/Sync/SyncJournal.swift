import Foundation

/// The local baseline is the last captured/applied database snapshot, not a remote winner.
/// Capture local edits before ingest, then refresh the baseline after applying resolved changes.
nonisolated struct FolderSyncState: Codable, Sendable {
    private(set) var operations: [SyncOperation] = []
    var baseline: [SyncRecordKey: Data] = [:]

    init() {}

    private enum CodingKeys: String, CodingKey { case operations, baseline }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let incoming = try container.decode([SyncOperation].self, forKey: .operations)
        baseline = try container.decode([SyncRecordKey: Data].self, forKey: .baseline)
        try ingest(incoming)
    }

    mutating func ingest(_ incoming: [SyncOperation]) throws {
        var known = Dictionary(uniqueKeysWithValues: operations.map { ($0.id, $0) })
        var additions: [SyncOperation] = []
        for operation in incoming {
            try Self.validate(operation)
            if let existing = known[operation.id] {
                guard existing == operation else { throw SyncProtocolError.duplicateOperation(operation.id) }
            } else {
                known[operation.id] = operation
                additions.append(operation)
            }
        }
        // Validate the whole candidate graph. A late parent can expose an invalid
        // relationship or cycle in an operation previously waiting for dependencies.
        try JournalGraph.validate(known)
        operations.append(contentsOf: additions)
    }

    mutating func captureLocal(_ snapshot: [SyncRecordKey: Data], deviceID: UUID, now: Date) throws -> [SyncOperation] {
        let graph = JournalGraph(operations)
        let changedKeys = Set(baseline.keys).union(snapshot.keys)
            .filter { baseline[$0] != snapshot[$0] }.sorted(by: Self.keyOrder)
        var additions: [SyncOperation] = []
        for key in changedKeys {
            let heads = graph.heads[key, default: []]
            let parents: [SyncOperation]
            if graph.incompleteKeys.contains(key) {
                // Do not let a checkpointed remote dependency prevent future reads.
                // Continue only known, complete local ancestry; remote versions stay
                // untouched and remain blocked until their ancestors arrive.
                if let localBaseline = baseline[key] {
                    parents = graph.completeBaselineVersions(key: key, payload: localBaseline)
                    guard !parents.isEmpty else { throw SyncProtocolError.ambiguousLocalVersion(key) }
                } else {
                    parents = []
                }
            } else if heads.contains(where: { $0.payload != baseline[key] }) {
                // An ordinary edit continues the local branch. Only explicit resolve
                // may parent all conflicting versions and discard the conflict.
                // Even a single complete remote head can be deferred by the record
                // store. Parent only ancestry matching the actual database baseline.
                parents = graph.completeBaselineVersions(key: key, payload: baseline[key])
                if baseline[key] != nil, parents.isEmpty {
                    throw SyncProtocolError.ambiguousLocalVersion(key)
                }
            } else {
                parents = heads
            }
            additions.append(SyncOperation(deviceID: deviceID, key: key,
                                           parents: parents.map(\.id), payload: snapshot[key], timestamp: now))
        }
        // Validation and mutation are atomic even if one changed record is blocked.
        try ingest(additions)
        baseline = snapshot
        return additions
    }

    func resolvedChanges() -> [SyncRecordChange] {
        let graph = JournalGraph(operations)
        return graph.heads.keys.sorted(by: Self.keyOrder).compactMap { key in
            let heads = graph.heads[key, default: []]
            guard !graph.incompleteKeys.contains(key), !Self.hasDifferentPayloads(heads),
                  let first = heads.first else { return nil }
            return SyncRecordChange(key: key, payload: first.payload)
        }
    }

    mutating func resolve(key: SyncRecordKey, payload: Data?, deviceID: UUID, now: Date) throws -> SyncOperation {
        let graph = JournalGraph(operations)
        guard !graph.incompleteKeys.contains(key) else { throw SyncProtocolError.missingDependencies(key) }
        let operation = SyncOperation(deviceID: deviceID, key: key,
                                      parents: graph.heads[key, default: []].map(\.id),
                                      payload: payload, timestamp: now)
        try ingest([operation])
        baseline[key] = payload
        return operation
    }

    var conflicts: [SyncConflict] {
        let graph = JournalGraph(operations)
        return graph.heads.keys.sorted(by: Self.keyOrder).compactMap { key in
            let heads = graph.heads[key, default: []]
            guard !graph.incompleteKeys.contains(key), Self.hasDifferentPayloads(heads) else { return nil }
            return SyncConflict(key: key, versions: heads)
        }
    }

    /// Number of operations waiting for a direct or transitive missing ancestor.
    var pendingDependencyCount: Int { JournalGraph(operations).incompleteIDs.count }

    private static func hasDifferentPayloads(_ heads: [SyncOperation]) -> Bool {
        guard let first = heads.first else { return false }
        return heads.dropFirst().contains { $0.payload != first.payload }
    }

    private static func keyOrder(_ lhs: SyncRecordKey, _ rhs: SyncRecordKey) -> Bool {
        if lhs.entity != rhs.entity { return lhs.entity.rawValue < rhs.entity.rawValue }
        return lhs.id < rhs.id
    }

    private static func validate(_ operation: SyncOperation) throws {
        guard operation.formatVersion == 1 else { throw SyncProtocolError.unsupportedVersion(operation.formatVersion) }
        guard !operation.key.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SyncProtocolError.invalidOperation("identificador de registro vazio")
        }
        guard operation.timestamp.timeIntervalSinceReferenceDate.isFinite else {
            throw SyncProtocolError.invalidOperation("data inválida")
        }
        guard !operation.parents.contains(operation.id) else {
            throw SyncProtocolError.invalidOperation("operação descendente de si mesma")
        }
        guard Set(operation.parents).count == operation.parents.count else {
            throw SyncProtocolError.invalidOperation("versões anteriores repetidas")
        }
    }
}

/// Iterative graph traversal avoids recursion through untrusted remote ancestry.
private nonisolated struct JournalGraph {
    private var known: [UUID: SyncOperation]
    var heads: [SyncRecordKey: [SyncOperation]] = [:]
    var incompleteIDs: Set<UUID> = []
    var incompleteKeys: Set<SyncRecordKey> = []

    init(_ operations: [SyncOperation]) {
        let known = Dictionary(uniqueKeysWithValues: operations.map { ($0.id, $0) })
        self.known = known
        let edges = Self.edges(known)
        var remaining = edges.remaining
        var queue = known.keys.filter { remaining[$0] == 0 }
        var index = 0
        let parentIDs = Set(operations.flatMap(\.parents))
        for operation in operations {
            if !parentIDs.contains(operation.id) { heads[operation.key, default: []].append(operation) }
            if operation.parents.contains(where: { known[$0] == nil }) { incompleteIDs.insert(operation.id) }
        }
        while index < queue.count {
            let id = queue[index]
            index += 1
            for child in edges.children[id, default: []] {
                if incompleteIDs.contains(id) { incompleteIDs.insert(child) }
                remaining[child, default: 0] -= 1
                if remaining[child] == 0 { queue.append(child) }
            }
        }
        for id in incompleteIDs {
            if let operation = known[id] { incompleteKeys.insert(operation.key) }
        }
        for key in Array(heads.keys) {
            heads[key]?.sort { $0.id.uuidString < $1.id.uuidString }
        }
    }

    /// Baseline versions may be hidden from heads by incomplete descendants.
    /// Keep only the maximal matching complete versions, even when intermediate
    /// ancestors carried different payloads.
    func completeBaselineVersions(key: SyncRecordKey, payload: Data?) -> [SyncOperation] {
        let candidates = known.values.filter {
            $0.key == key && $0.payload == payload && !incompleteIDs.contains($0.id)
        }
        var ancestors: Set<UUID> = []
        var stack = candidates.flatMap(\.parents)
        while let id = stack.popLast() {
            if ancestors.insert(id).inserted, let operation = known[id] {
                stack.append(contentsOf: operation.parents)
            }
        }
        return candidates.filter { !ancestors.contains($0.id) }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    static func validate(_ known: [UUID: SyncOperation]) throws {
        for operation in known.values {
            for parent in operation.parents {
                if let ancestor = known[parent], ancestor.key != operation.key {
                    throw SyncProtocolError.invalidOperation("versão anterior pertence a outro registro")
                }
            }
        }
        let edges = edges(known)
        var remaining = edges.remaining
        var queue = known.keys.filter { remaining[$0] == 0 }
        var index = 0
        while index < queue.count {
            let id = queue[index]
            index += 1
            for child in edges.children[id, default: []] {
                remaining[child, default: 0] -= 1
                if remaining[child] == 0 { queue.append(child) }
            }
        }
        guard queue.count == known.count else { throw SyncProtocolError.invalidOperation("ciclo entre versões") }
    }

    private static func edges(_ known: [UUID: SyncOperation]) -> (remaining: [UUID: Int], children: [UUID: [UUID]]) {
        var remaining: [UUID: Int] = [:]
        var children: [UUID: [UUID]] = [:]
        for operation in known.values {
            let receivedParents = operation.parents.filter { known[$0] != nil }
            remaining[operation.id] = receivedParents.count
            for parent in receivedParents { children[parent, default: []].append(operation.id) }
        }
        return (remaining, children)
    }
}
