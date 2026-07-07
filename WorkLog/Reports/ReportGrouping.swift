import Foundation

/// Define como as sessões são consolidadas no relatório.
enum ReportGrouping: String, CaseIterable, Identifiable {
    /// Uma linha por sessão (cada início/pausa gera uma linha).
    case detailed
    /// Uma linha por combinação de projeto + dia, somando durações e valores.
    case byProjectAndDay

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .detailed: return "Detalhado"
        case .byProjectAndDay: return "Resumido por projeto e dia"
        }
    }
}
