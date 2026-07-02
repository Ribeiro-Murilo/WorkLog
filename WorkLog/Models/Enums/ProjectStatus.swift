import Foundation

enum ProjectStatus: String, Codable, CaseIterable, Identifiable {
    case active = "active"
    case inProgress = "inProgress"
    case blocked = "blocked"
    case ready = "ready"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .active: return "Ativo"
        case .inProgress: return "Em execução"
        case .blocked: return "Impedimento"
        case .ready: return "Pronto"
        }
    }

    var symbolName: String {
        switch self {
        case .active: return "circle.fill"
        case .inProgress: return "arrow.triangle.2.circlepath"
        case .blocked: return "exclamationmark.triangle.fill"
        case .ready: return "checkmark.circle.fill"
        }
    }
}
