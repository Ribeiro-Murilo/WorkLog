import Foundation

enum AppDisplayMode: String, Codable, CaseIterable, Identifiable {
    case menuBar = "menuBar"
    case notch = "notch"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .menuBar: return "Barra de menu"
        case .notch: return "Notch (topo da tela)"
        }
    }
}
