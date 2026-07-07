import Foundation
import SwiftData

@MainActor
protocol InvoiceRepositoryProtocol {
    func fetchAll() throws -> [Invoice]
    func nextNumber() throws -> Int
    func hasOverlap(client: String, start: Date, end: Date, excluding id: UUID?) throws -> Bool
    func insert(_ invoice: Invoice) throws
    func update(_ invoice: Invoice) throws
    func delete(_ invoice: Invoice) throws
}

@MainActor
final class InvoiceRepository: InvoiceRepositoryProtocol {
    private let modelContext: ModelContext
    private let settingsRepository: SettingsRepositoryProtocol

    init(modelContext: ModelContext, settingsRepository: SettingsRepositoryProtocol) {
        self.modelContext = modelContext
        self.settingsRepository = settingsRepository
    }

    func fetchAll() throws -> [Invoice] {
        let descriptor = FetchDescriptor<Invoice>(
            sortBy: [SortDescriptor(\.number, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Próximo número sequencial. Baseado em um contador persistido nas configurações
    /// (não no maior número existente), para nunca ser reaproveitado após exclusões.
    func nextNumber() throws -> Int {
        let settings = try settingsRepository.current()
        let next = settings.lastInvoiceNumber + 1
        settings.lastInvoiceNumber = next
        try settingsRepository.save(settings)
        return next
    }

    /// Verifica se já existe fatura do mesmo cliente com período sobreposto.
    func hasOverlap(client: String, start: Date, end: Date, excluding id: UUID?) throws -> Bool {
        let descriptor = FetchDescriptor<Invoice>(
            predicate: #Predicate { invoice in
                invoice.client == client && invoice.periodStart < end && invoice.periodEnd > start
            }
        )
        let matches = try modelContext.fetch(descriptor)
        if let id {
            return matches.contains { $0.id != id }
        }
        return !matches.isEmpty
    }

    func insert(_ invoice: Invoice) throws {
        modelContext.insert(invoice)
        try modelContext.save()
    }

    func update(_ invoice: Invoice) throws {
        invoice.updatedAt = .now
        try modelContext.save()
    }

    func delete(_ invoice: Invoice) throws {
        modelContext.delete(invoice)
        try modelContext.save()
    }
}
