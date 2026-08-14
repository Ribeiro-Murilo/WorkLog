import Foundation
import SwiftData

struct StorageMigrationNotice: Equatable {
    enum Kind: Equatable {
        case conflict
        case failure
    }

    let kind: Kind
    let title: String
    let message: String
}

struct StorageDataSummary: Equatable {
    let projects: Int
    let sessions: Int
    let comments: Int
    let settings: Int
    let shortcuts: Int
    let reportPresets: Int
    let invoices: Int
    let hasCustomizedSettings: Bool
    let hasCustomizedShortcuts: Bool

    var hasUserData: Bool {
        projects > 0 ||
        sessions > 0 ||
        comments > 0 ||
        reportPresets > 0 ||
        invoices > 0 ||
        hasCustomizedSettings ||
        hasCustomizedShortcuts
    }

    var isEmptyForMigration: Bool {
        !hasUserData
    }
}

@MainActor
final class LegacyStorageMigrator {
    static let completionKey = "WorkLog.storageMigration.v1.completed"

    private let legacyStoreURL: URL
    private let userDefaults: UserDefaults
    private let fileManager: FileManager

    init(
        legacyStoreURL: URL? = nil,
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        self.userDefaults = userDefaults
        self.fileManager = fileManager
        self.legacyStoreURL = legacyStoreURL ?? Self.defaultLegacyStoreURL(fileManager: fileManager)
    }

    static func defaultLegacyStoreURL(fileManager: FileManager = .default) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Containers", isDirectory: true)
            .appendingPathComponent("RibeiroWorkes.WorkLog", isDirectory: true)
            .appendingPathComponent("Data", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("default.store", isDirectory: false)
    }

    func migrateIfNeeded(
        destinationContext: ModelContext,
        schema: Schema
    ) -> StorageMigrationNotice? {
        let destinationSummary: StorageDataSummary
        do {
            destinationSummary = try summary(for: destinationContext)
        } catch {
            return failureNotice(for: legacyStoreURL, error: error)
        }

        if userDefaults.bool(forKey: Self.completionKey), !destinationSummary.isEmptyForMigration {
            return nil
        }

        guard fileManager.fileExists(atPath: legacyStoreURL.path) else {
            return nil
        }

        do {
            let stagedStore = try stageLegacyStore()
            defer {
                try? fileManager.removeItem(at: stagedStore.directory)
            }

            let configuration = ModelConfiguration(
                "WorkLog legacy store",
                schema: schema,
                url: stagedStore.url,
                allowsSave: true,
                cloudKitDatabase: .none
            )
            let legacyContainer = try ModelContainer(for: schema, configurations: [configuration])
            let legacyContext = ModelContext(legacyContainer)
            return migrateIfNeeded(
                sourceContext: legacyContext,
                destinationContext: destinationContext,
                legacyURL: legacyStoreURL
            )
        } catch {
            return failureNotice(for: legacyStoreURL, error: error)
        }
    }

    private func stageLegacyStore() throws -> (directory: URL, url: URL) {
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("WorkLog-Legacy-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let sourceDirectory = legacyStoreURL.deletingLastPathComponent()
        let filename = legacyStoreURL.lastPathComponent
        for suffix in ["", "-wal", "-shm"] {
            let sourceURL = sourceDirectory.appendingPathComponent(filename + suffix)
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                continue
            }
            let destinationURL = directory.appendingPathComponent(filename + suffix)
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }

        return (directory, directory.appendingPathComponent(filename, isDirectory: false))
    }

    func migrateIfNeeded(
        sourceContext: ModelContext,
        destinationContext: ModelContext,
        legacyURL: URL? = nil
    ) -> StorageMigrationNotice? {
        do {
            let sourceSummary = try summary(for: sourceContext)
            guard sourceSummary.hasUserData else {
                return nil
            }

            let destinationSummary = try summary(for: destinationContext)
            if userDefaults.bool(forKey: Self.completionKey), !destinationSummary.isEmptyForMigration {
                return nil
            }

            guard destinationSummary.isEmptyForMigration else {
                return conflictNotice(for: legacyURL, source: sourceSummary, destination: destinationSummary)
            }

            do {
                try copyData(from: sourceContext, to: destinationContext)
                userDefaults.set(true, forKey: Self.completionKey)
                return nil
            } catch {
                destinationContext.rollback()
                return failureNotice(for: legacyURL ?? legacyStoreURL, error: error)
            }
        } catch {
            return failureNotice(for: legacyURL ?? legacyStoreURL, error: error)
        }
    }

    private func summary(for context: ModelContext) throws -> StorageDataSummary {
        let settings = try context.fetch(FetchDescriptor<AppSettings>())
        let shortcuts = try context.fetch(FetchDescriptor<ShortcutBinding>())

        return StorageDataSummary(
            projects: try context.fetch(FetchDescriptor<Project>()).count,
            sessions: try context.fetch(FetchDescriptor<Session>()).count,
            comments: try context.fetch(FetchDescriptor<Comment>()).count,
            settings: settings.count,
            shortcuts: shortcuts.count,
            reportPresets: try context.fetch(FetchDescriptor<ReportPreset>()).count,
            invoices: try context.fetch(FetchDescriptor<Invoice>()).count,
            hasCustomizedSettings: settings.contains(where: { !Self.isDefaultSettings($0) }),
            hasCustomizedShortcuts: !Self.areDefaultShortcuts(shortcuts)
        )
    }

    private func copyData(from source: ModelContext, to destination: ModelContext) throws {
        let sourceProjects = try source.fetch(FetchDescriptor<Project>())
        let sourceSessions = try source.fetch(FetchDescriptor<Session>())
        let sourceComments = try source.fetch(FetchDescriptor<Comment>())
        let sourceSettings = try source.fetch(FetchDescriptor<AppSettings>()).first
        let sourceShortcuts = try source.fetch(FetchDescriptor<ShortcutBinding>())
        let sourcePresets = try source.fetch(FetchDescriptor<ReportPreset>())
        let sourceInvoices = try source.fetch(FetchDescriptor<Invoice>())

        var projectsByID: [UUID: Project] = [:]
        for sourceProject in sourceProjects {
            let project = Project(
                name: sourceProject.name,
                client: sourceProject.client,
                dailyRate: sourceProject.dailyRate,
                category: sourceProject.category,
                tags: sourceProject.tags,
                descriptionText: sourceProject.descriptionText,
                status: sourceProject.status,
                isArchived: sourceProject.isArchived,
                isFavorite: sourceProject.isFavorite
            )
            project.id = sourceProject.id
            project.createdAt = sourceProject.createdAt
            project.updatedAt = sourceProject.updatedAt
            destination.insert(project)
            projectsByID[project.id] = project
        }

        for sourceSession in sourceSessions {
            let session = Session(
                project: sourceSession.project.flatMap { projectsByID[$0.id] },
                date: sourceSession.date,
                startTime: sourceSession.startTime,
                endTime: sourceSession.endTime,
                durationSeconds: sourceSession.durationSeconds,
                note: sourceSession.note,
                category: sourceSession.category,
                status: sourceSession.status
            )
            session.id = sourceSession.id
            session.createdAt = sourceSession.createdAt
            session.updatedAt = sourceSession.updatedAt
            destination.insert(session)
        }

        for sourceComment in sourceComments {
            let comment = Comment(
                text: sourceComment.text,
                author: sourceComment.author,
                project: sourceComment.project.flatMap { projectsByID[$0.id] }
            )
            comment.id = sourceComment.id
            comment.createdAt = sourceComment.createdAt
            destination.insert(comment)
        }

        if let sourceSettings {
            let destinationSettings = try destination.fetch(FetchDescriptor<AppSettings>()).first
            let settings = destinationSettings ?? AppSettings()
            settings.id = sourceSettings.id
            settings.launchAtLogin = sourceSettings.launchAtLogin
            settings.idleTimeoutMinutes = sourceSettings.idleTimeoutMinutes
            settings.showSeconds = sourceSettings.showSeconds
            settings.theme = sourceSettings.theme
            settings.timeFormat = sourceSettings.timeFormat
            settings.displayMode = sourceSettings.displayMode
            settings.lastBackupDate = sourceSettings.lastBackupDate
            settings.invoiceIssuerName = sourceSettings.invoiceIssuerName
            settings.invoiceIssuerDetails = sourceSettings.invoiceIssuerDetails
            settings.lastInvoiceNumber = sourceSettings.lastInvoiceNumber
            settings.includeLogoInPDF = sourceSettings.includeLogoInPDF
            settings.createdAt = sourceSettings.createdAt
            settings.updatedAt = sourceSettings.updatedAt
            if destinationSettings == nil {
                destination.insert(settings)
            }
        }

        let destinationShortcuts = try destination.fetch(FetchDescriptor<ShortcutBinding>())
        let destinationShortcutsByAction = Dictionary(
            destinationShortcuts.map { ($0.actionRawValue, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for sourceShortcut in sourceShortcuts {
            let shortcut = destinationShortcutsByAction[sourceShortcut.actionRawValue] ?? ShortcutBinding(
                action: sourceShortcut.action,
                keyCombo: sourceShortcut.keyCombo,
                isEnabled: sourceShortcut.isEnabled
            )
            shortcut.actionRawValue = sourceShortcut.actionRawValue
            shortcut.keyCode = sourceShortcut.keyCode
            shortcut.modifiers = sourceShortcut.modifiers
            shortcut.isEnabled = sourceShortcut.isEnabled
            shortcut.updatedAt = sourceShortcut.updatedAt
            if destinationShortcutsByAction[sourceShortcut.actionRawValue] == nil {
                destination.insert(shortcut)
            }
        }

        for sourcePreset in sourcePresets {
            let preset = ReportPreset(
                name: sourcePreset.name,
                columns: sourcePreset.columns,
                grouping: sourcePreset.grouping
            )
            preset.id = sourcePreset.id
            preset.columnsRaw = sourcePreset.columnsRaw
            preset.groupingRaw = sourcePreset.groupingRaw
            preset.createdAt = sourcePreset.createdAt
            preset.updatedAt = sourcePreset.updatedAt
            destination.insert(preset)
        }

        for sourceInvoice in sourceInvoices {
            let invoice = Invoice(
                number: sourceInvoice.number,
                client: sourceInvoice.client,
                issueDate: sourceInvoice.issueDate,
                periodStart: sourceInvoice.periodStart,
                periodEnd: sourceInvoice.periodEnd,
                lineItems: sourceInvoice.lineItems,
                notes: sourceInvoice.notes,
                status: sourceInvoice.status
            )
            invoice.id = sourceInvoice.id
            invoice.totalValue = sourceInvoice.totalValue
            invoice.createdAt = sourceInvoice.createdAt
            invoice.updatedAt = sourceInvoice.updatedAt
            destination.insert(invoice)
        }

        try destination.save()
    }

    private func conflictNotice(
        for legacyURL: URL?,
        source: StorageDataSummary,
        destination: StorageDataSummary
    ) -> StorageMigrationNotice {
        let path = legacyURL?.path ?? legacyStoreURL.path
        return StorageMigrationNotice(
            kind: .conflict,
            title: "Migração de dados não realizada",
            message: "O armazenamento atual e o armazenamento legado já contêm dados. O WorkLog não fez um merge automático para evitar duplicações ou sobrescritas. O banco legado foi preservado em:\n\n\(path)\n\nDados no legado: \(source.projects) projetos, \(source.sessions) sessões. Dados atuais: \(destination.projects) projetos, \(destination.sessions) sessões."
        )
    }

    private func failureNotice(for url: URL, error: Error) -> StorageMigrationNotice {
        StorageMigrationNotice(
            kind: .failure,
            title: "Não foi possível migrar os dados",
            message: "O WorkLog manteve o armazenamento legado intacto, mas não conseguiu concluir a migração. Você poderá tentar novamente depois.\n\nBanco legado:\n\(url.path)\n\nDetalhes: \(error.localizedDescription)"
        )
    }

    private static func isDefaultSettings(_ settings: AppSettings) -> Bool {
        let defaults = AppSettings()
        return settings.launchAtLogin == defaults.launchAtLogin &&
            settings.idleTimeoutMinutes == defaults.idleTimeoutMinutes &&
            settings.showSeconds == defaults.showSeconds &&
            settings.theme == defaults.theme &&
            settings.timeFormat == defaults.timeFormat &&
            settings.displayMode == defaults.displayMode &&
            settings.lastBackupDate == defaults.lastBackupDate &&
            settings.invoiceIssuerName == defaults.invoiceIssuerName &&
            settings.invoiceIssuerDetails == defaults.invoiceIssuerDetails &&
            settings.lastInvoiceNumber == defaults.lastInvoiceNumber &&
            settings.includeLogoInPDF == defaults.includeLogoInPDF
    }

    private static func areDefaultShortcuts(_ shortcuts: [ShortcutBinding]) -> Bool {
        shortcuts.allSatisfy { shortcut in
            guard
                let action = ShortcutAction(rawValue: shortcut.actionRawValue),
                let defaultCombo = ShortcutsService.defaultBindings[action]
            else {
                return false
            }
            return shortcut.keyCombo == defaultCombo && shortcut.isEnabled
        }
    }
}
