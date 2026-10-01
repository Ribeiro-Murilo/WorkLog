import Foundation
import SwiftData

@Model
final class FolderSyncMetadata {
    var scope: String = ""
    var stateData: Data = Data()

    init(scope: String = "", stateData: Data = Data()) {
        self.scope = scope
        self.stateData = stateData
    }
}

struct SyncInvoiceReference: Identifiable {
    let id: UUID
    let client: String
}

struct SyncInvoiceCollision: Identifiable {
    let number: Int
    let invoices: [SyncInvoiceReference]
    var id: Int { number }
}

@MainActor
protocol FolderSyncRecordStoreProtocol {
    func snapshot() throws -> [SyncRecordKey: Data]
    func apply(_ changes: [SyncRecordChange]) throws
    func loadState(scope: String) throws -> FolderSyncState?
    func saveState(_ state: FolderSyncState, scope: String) throws
    func rollback()
    func duplicateInvoiceNumbers() throws -> [SyncInvoiceCollision]
    func renumberInvoice(id: UUID) throws
}

enum SyncRecordStoreError: LocalizedError {
    case invalidRecord(SyncRecordKey)
    case missingProject(UUID)
    case runningSession(UUID)
    case runningProject(String)
    case invoiceNotFound
    case exhaustedInvoiceNumbers

    var errorDescription: String? {
        switch self {
        case .invalidRecord(let key): return "Registro inválido de \(key.entity.displayName): \(key.id)."
        case .missingProject(let id): return "Aguardando o projeto \(id.uuidString) antes de importar seus registros."
        case .runningSession: return "Sessões em execução pertencem a este Mac. Pause o cronômetro antes de sincronizar esta sessão."
        case .runningProject(let name): return "Pause o cronômetro do projeto \(name) antes de aplicar sua exclusão."
        case .invoiceNotFound: return "A fatura selecionada não existe mais."
        case .exhaustedInvoiceNumbers: return "O contador de faturas atingiu o limite permitido."
        }
    }
}

@MainActor
final class SwiftDataSyncRecordStore: FolderSyncRecordStoreProtocol {
    private let modelContext: ModelContext
    static let billingKey = SyncRecordKey(entity: .billingSettings, id: "issuer")

    init(modelContext: ModelContext) { self.modelContext = modelContext }

    func snapshot() throws -> [SyncRecordKey: Data] {
        var result: [SyncRecordKey: Data] = [:]
        func add<T: Encodable>(_ entity: SyncEntity, _ id: UUID, _ payload: T) throws {
            result[SyncRecordKey(entity: entity, id: id.uuidString)] = try SyncPayloadCodec.encode(payload)
        }
        for item in try modelContext.fetch(FetchDescriptor<Project>()) { try add(.project, item.id, ProjectSyncPayload(item)) }
        for item in try modelContext.fetch(FetchDescriptor<Session>()) where item.status != .running { try add(.session, item.id, SessionSyncPayload(item)) }
        for item in try modelContext.fetch(FetchDescriptor<Comment>()) { try add(.comment, item.id, CommentSyncPayload(item)) }
        for item in try modelContext.fetch(FetchDescriptor<ReportPreset>()) { try add(.reportPreset, item.id, ReportPresetSyncPayload(item)) }
        for item in try modelContext.fetch(FetchDescriptor<Invoice>()) { try add(.invoice, item.id, InvoiceSyncPayload(item)) }
        if let settings = try modelContext.fetch(FetchDescriptor<AppSettings>()).first,
           !settings.invoiceIssuerName.isEmpty || !settings.invoiceIssuerDetails.isEmpty {
            result[Self.billingKey] = try SyncPayloadCodec.encode(BillingSettingsSyncPayload(invoiceIssuerName: settings.invoiceIssuerName, invoiceIssuerDetails: settings.invoiceIssuerDetails))
        }
        return result
    }

    /// Stages a complete projection. saveState is the only commit boundary.
    func apply(_ changes: [SyncRecordChange]) throws {
        do { try stage(changes, allowRunningSessions: false) }
        catch { rollback(); throw error }
    }

    func loadState(scope: String) throws -> FolderSyncState? {
        guard let metadata = try modelContext.fetch(FetchDescriptor<FolderSyncMetadata>()).first(where: { $0.scope == scope }) else { return nil }
        return try SyncPayloadCodec.decode(FolderSyncState.self, from: metadata.stateData)
    }

    func saveState(_ state: FolderSyncState, scope: String) throws {
        do {
            // Include all historical versions, even conflicting or later deleted invoices.
            var highest = 0
            for operation in state.operations where operation.key.entity == .invoice {
                if let data = operation.payload {
                    let invoice = try SyncPayloadCodec.decode(InvoiceSyncPayload.self, from: data)
                    guard operation.key.id == invoice.id.uuidString, invoice.number >= 0 else { throw SyncRecordStoreError.invalidRecord(operation.key) }
                    highest = max(highest, invoice.number)
                }
            }
            try raiseInvoiceCounter(to: highest)
            let bytes = try SyncPayloadCodec.encode(state)
            let metadata = try modelContext.fetch(FetchDescriptor<FolderSyncMetadata>()).first(where: { $0.scope == scope }) ?? FolderSyncMetadata(scope: scope)
            metadata.stateData = bytes
            modelContext.insert(metadata)
            try modelContext.save()
        } catch { rollback(); throw error }
    }

    func rollback() { modelContext.rollback() }

    func duplicateInvoiceNumbers() throws -> [SyncInvoiceCollision] {
        let grouped = Dictionary(grouping: try modelContext.fetch(FetchDescriptor<Invoice>()), by: \.number)
        return grouped.filter { $0.value.count > 1 }.map { number, invoices in
            SyncInvoiceCollision(number: number, invoices: invoices.sorted { $0.id.uuidString < $1.id.uuidString }.map { SyncInvoiceReference(id: $0.id, client: $0.client) })
        }.sorted { $0.number < $1.number }
    }

    func renumberInvoice(id: UUID) throws {
        do {
            let invoices = try modelContext.fetch(FetchDescriptor<Invoice>())
            guard let invoice = invoices.first(where: { $0.id == id }) else { throw SyncRecordStoreError.invoiceNotFound }
            let settings = try currentSettings()
            let maximum = max(settings.lastInvoiceNumber, invoices.map(\.number).max() ?? 0)
            guard maximum < Int.max else { throw SyncRecordStoreError.exhaustedInvoiceNumbers }
            invoice.number = maximum + 1
            invoice.updatedAt = .now
            settings.lastInvoiceNumber = invoice.number
            try modelContext.save()
        } catch { rollback(); throw error }
    }

    func currentSettings() throws -> AppSettings {
        if let existing = try modelContext.fetch(FetchDescriptor<AppSettings>()).first { return existing }
        let settings = AppSettings()
        modelContext.insert(settings)
        return settings
    }

    func raiseInvoiceCounter(to historicalNumber: Int) throws {
        let maximum = max(historicalNumber, try modelContext.fetch(FetchDescriptor<Invoice>()).map(\.number).max() ?? 0)
        if maximum > 0 {
            let settings = try currentSettings()
            settings.lastInvoiceNumber = max(settings.lastInvoiceNumber, maximum)
        }
    }

    /// Also used by backup, which intentionally includes running sessions.
    func stage(_ changes: [SyncRecordChange], allowRunningSessions: Bool) throws {
        var projects = Dictionary(uniqueKeysWithValues: try modelContext.fetch(FetchDescriptor<Project>()).map { ($0.id, $0) })
        var sessions = Dictionary(uniqueKeysWithValues: try modelContext.fetch(FetchDescriptor<Session>()).map { ($0.id, $0) })
        var comments = Dictionary(uniqueKeysWithValues: try modelContext.fetch(FetchDescriptor<Comment>()).map { ($0.id, $0) })
        var presets = Dictionary(uniqueKeysWithValues: try modelContext.fetch(FetchDescriptor<ReportPreset>()).map { ($0.id, $0) })
        var invoices = Dictionary(uniqueKeysWithValues: try modelContext.fetch(FetchDescriptor<Invoice>()).map { ($0.id, $0) })
        let tombstones = Set(try changes.filter { $0.key.entity == .project && $0.payload == nil }.map { change -> UUID in
            guard let id = UUID(uuidString: change.key.id) else { throw SyncRecordStoreError.invalidRecord(change.key) }
            return id
        })
        for id in tombstones {
            if let project = projects[id], sessions.values.contains(where: { $0.project?.id == id && $0.status == .running }) {
                throw SyncRecordStoreError.runningProject(project.name)
            }
        }
        func decode<T: Decodable>(_ type: T.Type, _ change: SyncRecordChange, id: (T) -> UUID) throws -> T {
            guard let data = change.payload else { throw SyncRecordStoreError.invalidRecord(change.key) }
            let payload = try SyncPayloadCodec.decode(type, from: data)
            guard change.key.id == id(payload).uuidString else { throw SyncRecordStoreError.invalidRecord(change.key) }
            return payload
        }
        func parent(_ id: UUID?) throws -> Project? {
            guard let id else { return nil }
            guard let project = projects[id] else { throw SyncRecordStoreError.missingProject(id) }
            return project
        }
        // Materialize every parent first regardless of input order.
        for change in changes where change.key.entity == .project && change.payload != nil {
            let payload = try decode(ProjectSyncPayload.self, change, id: { $0.id })
            guard !tombstones.contains(payload.id) else { continue }
            let item = payload.materialize(existing: projects[payload.id]); modelContext.insert(item); projects[item.id] = item
        }
        for change in changes where change.key.entity != .project && change.payload != nil {
            switch change.key.entity {
            case .session:
                let payload = try decode(SessionSyncPayload.self, change, id: { $0.id })
                guard allowRunningSessions || payload.status != .running else { throw SyncRecordStoreError.runningSession(payload.id) }
                guard allowRunningSessions || sessions[payload.id]?.status != .running else { throw SyncRecordStoreError.runningSession(payload.id) }
                if let projectID = payload.projectId, tombstones.contains(projectID) {
                    if let existing = sessions[payload.id], existing.status != .running { modelContext.delete(existing); sessions[payload.id] = nil }
                    continue
                }
                let item = try payload.materialize(existing: sessions[payload.id], project: parent(payload.projectId)); modelContext.insert(item); sessions[item.id] = item
            case .comment:
                let payload = try decode(CommentSyncPayload.self, change, id: { $0.id })
                if let projectID = payload.projectId, tombstones.contains(projectID) {
                    if let existing = comments[payload.id] { modelContext.delete(existing); comments[payload.id] = nil }
                    continue
                }
                let item = try payload.materialize(existing: comments[payload.id], project: parent(payload.projectId)); modelContext.insert(item); comments[item.id] = item
            case .reportPreset:
                let payload = try decode(ReportPresetSyncPayload.self, change, id: { $0.id })
                let item = payload.materialize(existing: presets[payload.id]); modelContext.insert(item); presets[item.id] = item
            case .invoice:
                let payload = try decode(InvoiceSyncPayload.self, change, id: { $0.id })
                guard payload.number >= 0 else { throw SyncRecordStoreError.invalidRecord(change.key) }
                let item = payload.materialize(existing: invoices[payload.id]); modelContext.insert(item); invoices[item.id] = item
            case .billingSettings:
                guard change.key == Self.billingKey, let data = change.payload else { throw SyncRecordStoreError.invalidRecord(change.key) }
                let payload = try SyncPayloadCodec.decode(BillingSettingsSyncPayload.self, from: data)
                let settings = try currentSettings()
                settings.invoiceIssuerName = payload.invoiceIssuerName; settings.invoiceIssuerDetails = payload.invoiceIssuerDetails
            case .project: break
            }
        }
        // Delete children explicitly before their cascade parent; running timers are protected.
        for change in changes where change.payload == nil && change.key.entity != .project {
            if change.key.entity == .billingSettings {
                guard change.key == Self.billingKey else { throw SyncRecordStoreError.invalidRecord(change.key) }
                let settings = try currentSettings(); settings.invoiceIssuerName = ""; settings.invoiceIssuerDetails = ""
                continue
            }
            guard let id = UUID(uuidString: change.key.id) else { throw SyncRecordStoreError.invalidRecord(change.key) }
            switch change.key.entity {
            case .session:
                if let item = sessions[id] {
                    guard allowRunningSessions || item.status != .running else { throw SyncRecordStoreError.runningSession(id) }
                    modelContext.delete(item)
                }
            case .comment: if let item = comments[id] { modelContext.delete(item) }
            case .reportPreset: if let item = presets[id] { modelContext.delete(item) }
            case .invoice: if let item = invoices[id] { modelContext.delete(item) }
            default: break
            }
        }
        for id in tombstones { if let item = projects[id] { modelContext.delete(item) } }
    }
}
