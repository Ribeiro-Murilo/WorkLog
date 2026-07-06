import Foundation
import SwiftData

@MainActor
final class PersistenceController {
    static let shared = PersistenceController()

    let container: ModelContainer

    var mainContext: ModelContext {
        container.mainContext
    }

    private init(inMemory: Bool = false) {
        let schema = Schema([
            Project.self,
            Session.self,
            Comment.self,
            AppSettings.self,
            ShortcutBinding.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)

        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Não foi possível criar o ModelContainer: \(error)")
        }
    }

    static func preview() -> PersistenceController {
        PersistenceController(inMemory: true)
    }
}
