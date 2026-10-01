import Foundation

nonisolated enum SyncEntity: String, Codable, CaseIterable, Sendable {
    case project, session, comment, reportPreset, invoice, billingSettings

    var displayName: String {
        switch self {
        case .project: "Projeto"
        case .session: "Sessão"
        case .comment: "Comentário"
        case .reportPreset: "Preset de relatório"
        case .invoice: "Fatura"
        case .billingSettings: "Dados do emissor"
        }
    }
}

nonisolated struct SyncRecordKey: Codable, Hashable, Sendable {
    var entity: SyncEntity
    var id: String
}

nonisolated struct SyncOperation: Codable, Equatable, Identifiable, Sendable {
    var formatVersion: Int
    var id: UUID
    var deviceID: UUID
    var key: SyncRecordKey
    var parents: [UUID]
    var payload: Data?
    var timestamp: Date

    init(formatVersion: Int = 1, id: UUID = UUID(), deviceID: UUID, key: SyncRecordKey,
         parents: [UUID] = [], payload: Data?, timestamp: Date = Date()) {
        self.formatVersion = formatVersion
        self.id = id
        self.deviceID = deviceID
        self.key = key
        self.parents = parents
        self.payload = payload
        self.timestamp = timestamp
    }
}

nonisolated struct SyncRecordChange: Sendable {
    var key: SyncRecordKey
    var payload: Data?
}

nonisolated struct SyncConflict: Identifiable, Sendable {
    var key: SyncRecordKey
    var versions: [SyncOperation]
    var id: SyncRecordKey { key }
}

nonisolated enum SyncProtocolError: LocalizedError, Sendable {
    case unsupportedVersion(Int)
    case invalidOperation(String)
    case duplicateOperation(UUID)
    case missingDependencies(SyncRecordKey)
    case ambiguousLocalVersion(SyncRecordKey)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            "Formato de sincronização \(version) não suportado. Atualize o WorkLog nos Macs."
        case .invalidOperation(let reason):
            "Operação de sincronização inválida: \(reason)"
        case .duplicateOperation(let id):
            "A operação \(id) possui conteúdos diferentes. O histórico foi preservado."
        case .missingDependencies(let key):
            "Aguardando versões anteriores de \(key.entity.displayName.lowercased()) \(key.id)."
        case .ambiguousLocalVersion(let key):
            "Escolha uma versão do conflito de \(key.entity.displayName.lowercased()) \(key.id) antes de sincronizar esta edição."
        }
    }
}
