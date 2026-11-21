import Foundation

nonisolated enum ProjectCurrency: String, Codable, CaseIterable, Sendable {
    case brl = "BRL"
    case usd = "USD"
    case eur = "EUR"
}
