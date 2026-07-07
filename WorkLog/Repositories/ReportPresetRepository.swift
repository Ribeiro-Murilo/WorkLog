import Foundation
import SwiftData

@MainActor
protocol ReportPresetRepositoryProtocol {
    func fetchAll() throws -> [ReportPreset]
    func insert(_ preset: ReportPreset) throws
    func save() throws
    func delete(_ preset: ReportPreset) throws
}

@MainActor
final class ReportPresetRepository: ReportPresetRepositoryProtocol {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() throws -> [ReportPreset] {
        let descriptor = FetchDescriptor<ReportPreset>(
            sortBy: [SortDescriptor(\.name, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }

    func insert(_ preset: ReportPreset) throws {
        modelContext.insert(preset)
        try modelContext.save()
    }

    func save() throws {
        try modelContext.save()
    }

    func delete(_ preset: ReportPreset) throws {
        modelContext.delete(preset)
        try modelContext.save()
    }
}
