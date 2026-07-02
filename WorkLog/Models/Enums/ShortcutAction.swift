import Foundation

enum ShortcutAction: String, Codable, CaseIterable, Identifiable {
    case startTimer = "startTimer"
    case pauseTimer = "pauseTimer"
    case openDashboard = "openDashboard"
    case openPopover = "openPopover"
    case searchProject = "searchProject"
    case newProject = "newProject"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .startTimer: return "Iniciar timer"
        case .pauseTimer: return "Pausar timer"
        case .openDashboard: return "Abrir Dashboard"
        case .openPopover: return "Abrir Popover"
        case .searchProject: return "Pesquisar projeto"
        case .newProject: return "Novo projeto"
        }
    }
}
