import Foundation

enum InvoiceStatus: String, Codable, CaseIterable, Identifiable {
    case pending
    case paid

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pending: return "Pendente"
        case .paid: return "Paga"
        }
    }
}
