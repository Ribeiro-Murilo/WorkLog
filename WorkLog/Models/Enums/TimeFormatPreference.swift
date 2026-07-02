import Foundation

enum TimeFormatPreference: String, Codable, CaseIterable, Identifiable {
    case twelveHour = "twelveHour"
    case twentyFourHour = "twentyFourHour"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .twelveHour: return "12 horas"
        case .twentyFourHour: return "24 horas"
        }
    }
}
