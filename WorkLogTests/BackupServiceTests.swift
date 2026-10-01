import Foundation
import SwiftData
import Testing
@testable import WorkLog

@Suite(.serialized) @MainActor
struct BackupServiceTests {
    @Test func completeBackupRoundTripsAllEntitiesAndPreservesIDsOnRepeatedImport() throws {
        let context = try makeSyncRecordContext()
        let project = Project(name: "All", client: "Client", dailyRate: 123, category: .work)
        context.insert(project)
        context.insert(Session(project: project, date: .now, startTime: .now, category: .work))
        context.insert(WorkLog.Comment(text: "body", author: "who", project: project))
        context.insert(ReportPreset(name: "Preset", columns: [], grouping: .detailed))
        context.insert(Invoice(number: 8, client: "Client", periodStart: .now, periodEnd: .now, lineItems: [InvoiceLineItem(date: .now, projectName: "Snapshot", durationSeconds: 10, value: 42)]))
        let settings = AppSettings(launchAtLogin: false, idleTimeoutMinutes: 25, invoiceIssuerName: "Issuer")
        settings.includeLogoInPDF = true; settings.lastInvoiceNumber = 20
        context.insert(settings)
        context.insert(ShortcutBinding(action: .pauseTimer, keyCombo: KeyCombo(keyCode: 9, modifiers: 12)))
        try context.save()
        let service = BackupService(modelContext: context)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        try service.exportBackup(to: url)
        let first = try Data(contentsOf: url)
        let projectID = project.id
        try context.delete(model: Session.self); try context.delete(model: WorkLog.Comment.self); try context.delete(model: Project.self)
        try context.delete(model: ReportPreset.self); try context.delete(model: Invoice.self)
        try context.delete(model: AppSettings.self); try context.delete(model: ShortcutBinding.self)
        try context.save()
        try service.importBackup(from: url); try service.importBackup(from: url)
        #expect(try context.fetch(FetchDescriptor<Project>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<Project>()).first?.id == projectID)
        #expect(try context.fetch(FetchDescriptor<Session>()).first?.status == .running)
        #expect(try context.fetch(FetchDescriptor<WorkLog.Comment>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<ReportPreset>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<Invoice>()).first?.lineItems.first?.projectName == "Snapshot")
        #expect(try context.fetch(FetchDescriptor<ShortcutBinding>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<AppSettings>()).first?.includeLogoInPDF == true)
        #expect(try context.fetch(FetchDescriptor<AppSettings>()).first?.lastInvoiceNumber == 20)
        #expect(!first.isEmpty)
    }

    @Test func malformedRelationshipRollsBackArchiveAndFutureFormatIsRejected() throws {
        let context = try makeSyncRecordContext()
        let project = Project(name: "Original", client: "", dailyRate: 1, category: .work)
        context.insert(project)
        context.insert(Session(project: project, date: .now, startTime: .now, category: .work, status: .completed))
        try context.save()
        let service = BackupService(modelContext: context)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        try service.exportBackup(to: url)
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var projects = try #require(object["projects"] as? [[String: Any]])
        projects[0]["name"] = "Must rollback"; object["projects"] = projects
        var sessions = try #require(object["sessions"] as? [[String: Any]])
        sessions[0]["projectId"] = UUID().uuidString; object["sessions"] = sessions
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        #expect(throws: (any Error).self) { try service.importBackup(from: url) }
        #expect(try context.fetch(FetchDescriptor<Project>()).first?.name == "Original")
        object["formatVersion"] = 999
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        #expect(throws: (any Error).self) { try service.importBackup(from: url) }
        #expect(try context.fetch(FetchDescriptor<Project>()).count == 1)
    }

    @Test func archiveSettingsReplaceEffectivePreferencesAndCounterNeverDecreases() throws {
        let context = try makeSyncRecordContext()
        let archived = AppSettings(launchAtLogin: false, idleTimeoutMinutes: 99)
        archived.lastInvoiceNumber = 10
        context.insert(archived); try context.save()
        let archivedID = archived.id
        let service = BackupService(modelContext: context)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        try service.exportBackup(to: url)
        context.delete(archived)
        let local = AppSettings(); local.lastInvoiceNumber = 50
        context.insert(local); try context.save()
        try service.importBackup(from: url)
        let all = try context.fetch(FetchDescriptor<AppSettings>())
        #expect(all.count == 1)
        #expect(all.first?.id == archivedID)
        #expect(all.first?.idleTimeoutMinutes == 99)
        #expect(all.first?.lastInvoiceNumber == 50)
    }

    @Test func legacyBackupPreservesProjectAndSessionIDs() throws {
        let context = try makeSyncRecordContext()
        let projectID = UUID(), sessionID = UUID()
        let data = """
        {"exportedAt":"2026-10-01T00:00:00Z","projects":[{"id":"\(projectID)","name":"Old","client":"Acme","dailyRate":1,"category":"work","tags":[],"descriptionText":"","status":"active","isArchived":false,"isFavorite":true}],"sessions":[{"id":"\(sessionID)","projectId":"\(projectID)","date":"2026-10-01T00:00:00Z","startTime":"2026-10-01T00:00:00Z","durationSeconds":10,"note":"Old","category":"work","status":"completed"}]}
        """.data(using: .utf8)!
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)
        let service = BackupService(modelContext: context)
        try service.importBackup(from: url); try service.importBackup(from: url)
        #expect(try context.fetch(FetchDescriptor<Project>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<Project>()).first?.id == projectID)
        #expect(try context.fetch(FetchDescriptor<Session>()).first?.id == sessionID)
        #expect(try context.fetch(FetchDescriptor<Session>()).first?.project?.id == projectID)
    }
}
