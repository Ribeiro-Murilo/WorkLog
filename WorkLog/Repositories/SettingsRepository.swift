import Foundation
import SwiftData

@MainActor
protocol SettingsRepositoryProtocol {
    func current() throws -> AppSettings
    func save(_ settings: AppSettings) throws
}

@MainActor
final class SettingsRepository: SettingsRepositoryProtocol {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func current() throws -> AppSettings {
        var descriptor = FetchDescriptor<AppSettings>()
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }
        let settings = AppSettings()
        modelContext.insert(settings)
        try modelContext.save()
        return settings
    }

    func save(_ settings: AppSettings) throws {
        settings.updatedAt = .now
        try modelContext.save()
    }
}
