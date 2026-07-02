import Foundation

enum DashboardSidebarSection: String, CaseIterable, Identifiable, Hashable {
    case summary
    case projects
    case reports

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .summary: return "Resumo"
        case .projects: return "Projetos"
        case .reports: return "Relatórios"
        }
    }

    var symbolName: String {
        switch self {
        case .summary: return "square.grid.2x2"
        case .projects: return "folder"
        case .reports: return "chart.bar.doc.horizontal"
        }
    }
}
