import Foundation
import SwiftData

@MainActor
final class PersistenceController {
    static let shared = PersistenceController()

    let container: ModelContainer
    let migrationNotice: StorageMigrationNotice?

    var mainContext: ModelContext {
        container.mainContext
    }

    private init(inMemory: Bool = false) {
        let schema = Self.schema()
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            self.container = container
            migrationNotice = inMemory
                ? nil
                : LegacyStorageMigrator().migrateIfNeeded(
                    destinationContext: container.mainContext,
                    schema: schema
                )
        } catch {
            fatalError("Não foi possível criar o ModelContainer: \(error)")
        }
    }

    static func schema() -> Schema {
        Schema([
            Project.self,
            Session.self,
            Comment.self,
            AppSettings.self,
            ShortcutBinding.self,
            ReportPreset.self,
            Invoice.self,
        ])
    }

    static func preview() -> PersistenceController {
        PersistenceController(inMemory: true)
    }
}
