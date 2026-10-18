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

    /// Valor fechado acumulado, inclusive dos trechos anteriores de um timer retomado.
    var totalValue: Decimal {
        (sessions ?? []).reduce(Decimal(0)) { total, session in
            guard session.status == .running else { return total + session.estimatedValue }
            guard dailyRate > 0 else { return total }
            return total + dailyRate * Decimal(session.recordedDuration() / 3600 / Self.standardWorkdayHours)
        }
    }

    /// Trechos fechados continuam no total durante a execução da mesma sessão.
    var totalWorkedSeconds: TimeInterval {
        (sessions ?? []).reduce(0) { total, session in
            total + (session.status == .running ? session.recordedDuration() : session.durationSeconds)
        }
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
