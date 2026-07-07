import Foundation
import SwiftData

/// Linha congelada de uma fatura: fotografia dos dados da sessão/projeto no momento
/// da emissão. Não referencia `Session`/`Project` para que edições ou exclusões
/// posteriores não alterem uma fatura já emitida.
struct InvoiceLineItem: Codable, Hashable, Identifiable {
    var date: Date
    var projectName: String
    var durationSeconds: TimeInterval
    var value: Decimal

    var id: Self { self }
}

@Model
final class Invoice {
    var id: UUID = UUID()
    var number: Int = 0
    var client: String = ""
    var issueDate: Date = Date.now
    var periodStart: Date = Date.now
    var periodEnd: Date = Date.now
    var lineItems: [InvoiceLineItem] = []
    var totalValue: Decimal = 0
    var status: InvoiceStatus = InvoiceStatus.pending
    var notes: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    var totalDurationSeconds: TimeInterval {
        lineItems.reduce(0) { $0 + $1.durationSeconds }
    }

    var formattedNumber: String {
        "FAT-\(String(format: "%04d", number))"
    }

    init(
        number: Int,
        client: String,
        issueDate: Date = .now,
        periodStart: Date,
        periodEnd: Date,
        lineItems: [InvoiceLineItem],
        notes: String = "",
        status: InvoiceStatus = .pending
    ) {
        self.id = UUID()
        self.number = number
        self.client = client
        self.issueDate = issueDate
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.lineItems = lineItems
        self.totalValue = lineItems.reduce(Decimal(0)) { $0 + $1.value }
        self.notes = notes
        self.status = status
        self.createdAt = .now
        self.updatedAt = .now
    }
}
