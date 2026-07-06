import Foundation
import SwiftData

@Model
final class Project {
    var id: UUID = UUID()
    var name: String = ""
    var client: String = ""
    var dailyRate: Decimal = 0
    var category: ProjectCategory = ProjectCategory.work
    var tags: [String] = []
    var descriptionText: String = ""
    var status: ProjectStatus = ProjectStatus.active
    var isArchived: Bool = false
    var isFavorite: Bool = false
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \Session.project)
    var sessions: [Session]? = []

    @Relationship(deleteRule: .cascade, inverse: \Comment.project)
    var comments: [Comment]? = []

    /// Jornada padrão (em horas) usada para converter "Valor por dia" em valor por sessão.
    static let standardWorkdayHours: Double = 8

    /// Valor total já acumulado no projeto, calculado a partir das sessões encerradas ou pausadas.
    var totalValue: Decimal {
        (sessions ?? [])
            .filter { $0.status != .running }
            .reduce(Decimal(0)) { $0 + $1.estimatedValue }
    }

    /// Tempo total já trabalhado no projeto (sessões encerradas ou pausadas).
    var totalWorkedSeconds: TimeInterval {
        (sessions ?? [])
            .filter { $0.status != .running }
            .reduce(0) { $0 + $1.durationSeconds }
    }

    init(
        name: String,
        client: String,
        dailyRate: Decimal,
        category: ProjectCategory,
        tags: [String] = [],
        descriptionText: String = "",
        status: ProjectStatus = .active,
        isArchived: Bool = false,
        isFavorite: Bool = false
    ) {
        self.id = UUID()
        self.name = name
        self.client = client
        self.dailyRate = dailyRate
        self.category = category
        self.tags = tags
        self.descriptionText = descriptionText
        self.status = status
        self.isArchived = isArchived
        self.isFavorite = isFavorite
        self.createdAt = .now
        self.updatedAt = .now
    }
}
