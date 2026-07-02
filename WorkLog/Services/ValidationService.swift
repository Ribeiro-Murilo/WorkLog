import Foundation

enum ValidationError: LocalizedError {
    case emptyName
    case emptyClient
    case negativeRate
    case duplicateProject
    case invalidDateRange
    case overlappingSession
    case missingProject

    var errorDescription: String? {
        switch self {
        case .emptyName: return "O nome do projeto não pode estar vazio."
        case .emptyClient: return "O cliente não pode estar vazio."
        case .negativeRate: return "O valor por dia não pode ser negativo."
        case .duplicateProject: return "Já existe um projeto com esse nome para esse cliente."
        case .invalidDateRange: return "A hora final deve ser posterior à hora inicial."
        case .overlappingSession: return "Já existe uma sessão registrada nesse período."
        case .missingProject: return "Selecione um projeto para a sessão."
        }
    }
}

protocol ValidationServiceProtocol {
    func validateProjectFields(name: String, client: String, dailyRate: Decimal) throws
    func validateSessionFields(project: Project?, startTime: Date, endTime: Date?) throws
}

struct ValidationService: ValidationServiceProtocol {
    func validateProjectFields(name: String, client: String, dailyRate: Decimal) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedClient = client.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else { throw ValidationError.emptyName }
        guard !trimmedClient.isEmpty else { throw ValidationError.emptyClient }
        guard dailyRate >= 0 else { throw ValidationError.negativeRate }
    }

    func validateSessionFields(project: Project?, startTime: Date, endTime: Date?) throws {
        guard project != nil else { throw ValidationError.missingProject }
        if let endTime {
            guard endTime > startTime else { throw ValidationError.invalidDateRange }
        }
    }
}
