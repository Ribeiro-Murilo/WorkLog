import Foundation
import SwiftData

private struct WorkLogBackupArchive: Codable {
    var formatVersion: Int = 3
    var exportedAt: Date
    var projects: [ProjectSyncPayload]
    var sessions: [SessionSyncPayload]
    var comments: [CommentSyncPayload]
    var reportPresets: [ReportPresetSyncPayload]
    var invoices: [InvoiceSyncPayload]
    var settings: [AppSettingsSyncPayload]
    var shortcuts: [ShortcutBindingSyncPayload]
}

private enum BackupArchiveError: LocalizedError {
    case unsupportedVersion
    case invalidArchive
    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return "Este backup foi criado por uma versão mais recente do WorkLog."
        case .invalidArchive: return "O arquivo de backup contém registros inválidos ou repetidos."
        }
    }
}

@MainActor
protocol BackupServiceProtocol {
    func exportBackup(to url: URL) throws
    func importBackup(from url: URL) throws
}

@MainActor
final class BackupService: BackupServiceProtocol {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) { self.modelContext = modelContext }

    func exportBackup(to url: URL) throws {
        let archive = WorkLogBackupArchive(
            exportedAt: .now,
            projects: try modelContext.fetch(FetchDescriptor<Project>()).sorted { $0.id.uuidString < $1.id.uuidString }
                .map { ProjectSyncPayload($0, includeBaseCurrency: true) },
            sessions: try modelContext.fetch(FetchDescriptor<Session>()).sorted { $0.id.uuidString < $1.id.uuidString }
                .map { SessionSyncPayload($0, includeProjectCurrency: false) },
            comments: try modelContext.fetch(FetchDescriptor<Comment>()).sorted { $0.id.uuidString < $1.id.uuidString }.map(CommentSyncPayload.init),
            reportPresets: try modelContext.fetch(FetchDescriptor<ReportPreset>()).sorted { $0.id.uuidString < $1.id.uuidString }.map(ReportPresetSyncPayload.init),
            invoices: try modelContext.fetch(FetchDescriptor<Invoice>()).sorted { $0.id.uuidString < $1.id.uuidString }
                .map { InvoiceSyncPayload($0, includeBaseCurrency: true) },
            settings: try modelContext.fetch(FetchDescriptor<AppSettings>()).sorted { $0.id.uuidString < $1.id.uuidString }.map(AppSettingsSyncPayload.init),
            shortcuts: try modelContext.fetch(FetchDescriptor<ShortcutBinding>()).sorted { $0.actionRawValue < $1.actionRawValue }.map(ShortcutBindingSyncPayload.init)
        )
        try SyncPayloadCodec.encode(archive).write(to: url, options: .atomic)
    }

    func importBackup(from url: URL) throws {
        // Fully decode and validate before touching the context.
        let archive = try decodeArchive(Data(contentsOf: url))
        let store = SwiftDataSyncRecordStore(modelContext: modelContext)
        do {
            var changes: [SyncRecordChange] = []
            func append<T: Encodable>(_ entity: SyncEntity, _ records: [T], id: (T) -> UUID) throws {
                let ids = records.map(id)
                guard Set(ids).count == ids.count else { throw BackupArchiveError.invalidArchive }
                for record in records { changes.append(SyncRecordChange(key: SyncRecordKey(entity: entity, id: id(record).uuidString), payload: try SyncPayloadCodec.encode(record))) }
            }
            try append(.project, archive.projects, id: { $0.id })
            try append(.session, archive.sessions, id: { $0.id })
            try append(.comment, archive.comments, id: { $0.id })
            try append(.reportPreset, archive.reportPresets, id: { $0.id })
            try append(.invoice, archive.invoices, id: { $0.id })
            guard Set(archive.settings.map(\.id)).count == archive.settings.count,
                  Set(archive.shortcuts.map(\.actionRawValue)).count == archive.shortcuts.count,
                  archive.shortcuts.allSatisfy({ ShortcutAction(rawValue: $0.actionRawValue) != nil }) else {
                throw BackupArchiveError.invalidArchive
            }
            let previousMaximum = try modelContext.fetch(FetchDescriptor<AppSettings>()).map(\.lastInvoiceNumber).max() ?? 0
            try store.stage(changes, allowRunningSessions: true)
            let existingSettings = try modelContext.fetch(FetchDescriptor<AppSettings>())
            if !archive.settings.isEmpty {
                let restoredIDs = Set(archive.settings.map(\.id))
                for item in existingSettings where !restoredIDs.contains(item.id) { modelContext.delete(item) }
            }
            var settingsByID = Dictionary(uniqueKeysWithValues: existingSettings.filter { !$0.isDeleted }.map { ($0.id, $0) })
            for payload in archive.settings {
                let item = payload.materialize(existing: settingsByID[payload.id]); modelContext.insert(item); settingsByID[item.id] = item
            }
            var shortcutsByAction = Dictionary(uniqueKeysWithValues: try modelContext.fetch(FetchDescriptor<ShortcutBinding>()).map { ($0.actionRawValue, $0) })
            for payload in archive.shortcuts {
                let item = payload.materialize(existing: shortcutsByAction[payload.actionRawValue]); modelContext.insert(item); shortcutsByAction[item.actionRawValue] = item
            }
            try store.raiseInvoiceCounter(to: max(previousMaximum, archive.settings.map(\.lastInvoiceNumber).max() ?? 0))
            try modelContext.save()
        } catch { modelContext.rollback(); throw error }
    }

    private func decodeArchive(_ data: Data) throws -> WorkLogBackupArchive {
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw BackupArchiveError.invalidArchive }
        let formatVersion: Int
        if let version = object["formatVersion"] {
            guard let number = version as? Int, (1...3).contains(number) else { throw BackupArchiveError.unsupportedVersion }
            formatVersion = number
        } else {
            formatVersion = 1
        }
        if formatVersion == 3 {
            let archive = try SyncPayloadCodec.decode(WorkLogBackupArchive.self, from: data)
            guard archive.projects.allSatisfy({ $0.currencyCode != nil }),
                  archive.invoices.allSatisfy({ $0.currencyCode != nil }) else { throw BackupArchiveError.invalidArchive }
            return archive
        }
        if formatVersion == 2 {
            var archive = try SyncPayloadCodec.decode(WorkLogBackupArchive.self, from: data)
            for index in archive.projects.indices { archive.projects[index].currencyCode = nil }
            for index in archive.invoices.indices { archive.invoices[index].currencyCode = nil }
            return archive
        }
        // Original JSON backups used ISO8601 dates and omitted creation/update timestamps.
        guard let exportedAt = object["exportedAt"] as? String,
              var projects = object["projects"] as? [[String: Any]],
              var sessions = object["sessions"] as? [[String: Any]] else { throw BackupArchiveError.invalidArchive }
        for index in projects.indices {
            projects[index]["createdAt"] = projects[index]["createdAt"] ?? exportedAt
            projects[index]["updatedAt"] = projects[index]["updatedAt"] ?? exportedAt
            projects[index].removeValue(forKey: "currencyCode")
        }
        for index in sessions.indices {
            sessions[index]["createdAt"] = sessions[index]["createdAt"] ?? exportedAt
            sessions[index]["updatedAt"] = sessions[index]["updatedAt"] ?? exportedAt
        }
        object["formatVersion"] = 1
        object["projects"] = projects; object["sessions"] = sessions
        object["comments"] = []; object["reportPresets"] = []; object["invoices"] = []; object["settings"] = []; object["shortcuts"] = []
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WorkLogBackupArchive.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
