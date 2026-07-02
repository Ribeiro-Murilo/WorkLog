import Foundation

enum SessionStatus: String, Codable, CaseIterable, Identifiable {
    case running = "running"
    case paused = "paused"
    case completed = "completed"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .running: return "Em andamento"
        case .paused: return "Pausada"
        case .completed: return "Concluída"
        }
    }
}
