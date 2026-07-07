import Testing
import Foundation
@testable import WorkLog

@MainActor
struct InvoiceRepositoryTests {
    private func makeInvoice(number: Int, client: String = "Acme") -> Invoice {
        Invoice(
            number: number,
            client: client,
            periodStart: .now,
            periodEnd: .now,
            lineItems: [InvoiceLineItem(date: .now, projectName: "Alpha", durationSeconds: 3600, value: 100)]
        )
    }

    @Test func nextNumberStartsAtOne() throws {
        let context = makeInMemoryContext()
        let repo = InvoiceRepository(modelContext: context, settingsRepository: SettingsRepository(modelContext: context))
        #expect(try repo.nextNumber() == 1)
    }

    @Test func nextNumberNeverReusesAfterDeletion() throws {
        let context = makeInMemoryContext()
        let repo = InvoiceRepository(modelContext: context, settingsRepository: SettingsRepository(modelContext: context))
        let first = makeInvoice(number: try repo.nextNumber())
        try repo.insert(first)

        let second = makeInvoice(number: try repo.nextNumber())
        try repo.insert(second)
        #expect(second.number == 2)

        try repo.delete(second)

        #expect(try repo.nextNumber() == 3)
    }

    @Test func totalValueComputedFromLineItems() throws {
        let context = makeInMemoryContext()
        let repo = InvoiceRepository(modelContext: context, settingsRepository: SettingsRepository(modelContext: context))
        let invoice = Invoice(
            number: 1,
            client: "Acme",
            periodStart: .now,
            periodEnd: .now,
            lineItems: [
                InvoiceLineItem(date: .now, projectName: "Alpha", durationSeconds: 3600, value: 100),
                InvoiceLineItem(date: .now, projectName: "Beta", durationSeconds: 1800, value: 50),
            ]
        )
        try repo.insert(invoice)

        #expect(invoice.totalValue == 150)
        #expect(invoice.totalDurationSeconds == 5400)
    }

    @Test func hasOverlapDetectsIntersectingPeriodsForSameClient() throws {
        let context = makeInMemoryContext()
        let repo = InvoiceRepository(modelContext: context, settingsRepository: SettingsRepository(modelContext: context))
        let calendar = Calendar.current
        let day = { (offset: Int) in calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: .now))! }

        let invoice = Invoice(number: 1, client: "Acme", periodStart: day(10), periodEnd: day(20), lineItems: [])
        try repo.insert(invoice)

        #expect(try repo.hasOverlap(client: "Acme", start: day(15), end: day(25), excluding: nil))
        #expect(try !repo.hasOverlap(client: "Acme", start: day(21), end: day(25), excluding: nil))
        #expect(try !repo.hasOverlap(client: "Other", start: day(15), end: day(25), excluding: nil))
        #expect(try !repo.hasOverlap(client: "Acme", start: day(10), end: day(20), excluding: invoice.id))
    }

    @Test func deleteRemovesInvoice() throws {
        let context = makeInMemoryContext()
        let repo = InvoiceRepository(modelContext: context, settingsRepository: SettingsRepository(modelContext: context))
        let invoice = makeInvoice(number: 1)
        try repo.insert(invoice)

        try repo.delete(invoice)

        #expect(try repo.fetchAll().isEmpty)
    }
}
