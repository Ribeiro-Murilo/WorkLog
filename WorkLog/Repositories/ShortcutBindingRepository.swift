import Foundation
import SwiftData

@MainActor
protocol ShortcutBindingRepositoryProtocol {
    func fetchAll() throws -> [ShortcutBinding]
    func fetch(for action: ShortcutAction) throws -> ShortcutBinding?
    func save(_ binding: ShortcutBinding) throws
    func upsert(action: ShortcutAction, keyCombo: KeyCombo, isEnabled: Bool) throws -> ShortcutBinding
}

@MainActor
final class ShortcutBindingRepository: ShortcutBindingRepositoryProtocol {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() throws -> [ShortcutBinding] {
        try modelContext.fetch(FetchDescriptor<ShortcutBinding>())
    }

    func fetch(for action: ShortcutAction) throws -> ShortcutBinding? {
        let rawValue = action.rawValue
        let descriptor = FetchDescriptor<ShortcutBinding>(
            predicate: #Predicate { $0.actionRawValue == rawValue }
        )
        return try modelContext.fetch(descriptor).first
    }

    func save(_ binding: ShortcutBinding) throws {
        binding.updatedAt = .now
        try modelContext.save()
    }

    func upsert(action: ShortcutAction, keyCombo: KeyCombo, isEnabled: Bool) throws -> ShortcutBinding {
        if let existing = try fetch(for: action) {
            existing.keyCombo = keyCombo
            existing.isEnabled = isEnabled
            try save(existing)
            return existing
        }
        let binding = ShortcutBinding(action: action, keyCombo: keyCombo, isEnabled: isEnabled)
        modelContext.insert(binding)
        try modelContext.save()
        return binding
    }
}
