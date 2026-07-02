import Foundation

enum ProjectCategory: String, Codable, CaseIterable, Identifiable {
    case work = "work"
    case personal = "personal"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .work: return "Trabalho"
        case .personal: return "Pessoal"
        }
    }

    var symbolName: String {
        switch self {
        case .work: return "briefcase.fill"
        case .personal: return "person.fill"
        }
    }
}
