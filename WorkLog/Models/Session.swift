import Foundation
import SwiftData

@Model
final class Session {
    var id: UUID = UUID()
    var project: Project?
    var date: Date = Date.now
    var startTime: Date = Date.now
    var endTime: Date?
    var durationSeconds: TimeInterval = 0
    var note: String = ""
    var category: ProjectCategory = ProjectCategory.work
    var status: SessionStatus = SessionStatus.running
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(
        project: Project?,
        date: Date,
        startTime: Date,
        endTime: Date? = nil,
        durationSeconds: TimeInterval = 0,
        note: String = "",
        category: ProjectCategory,
        status: SessionStatus = .running
    ) {
        self.id = UUID()
        self.project = project
        self.date = date
        self.startTime = startTime
        self.endTime = endTime
        self.durationSeconds = durationSeconds
        self.note = note
        self.category = category
        self.status = status
        self.createdAt = .now
        self.updatedAt = .now
    }

    /// Valor estimado da sessão com base no "Valor por dia" do projeto,
    /// assumindo uma jornada padrão de `Project.standardWorkdayHours`.
    var estimatedValue: Decimal {
        guard let dailyRate = project?.dailyRate, dailyRate > 0 else { return 0 }
        let hoursWorked = durationSeconds / 3600
        return dailyRate * Decimal(hoursWorked / Project.standardWorkdayHours)
    }
}
