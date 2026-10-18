import Foundation
import SwiftData

/// Um trecho de trabalho. `end == nil` representa somente o trecho em execução.
struct SessionWorkPeriod: Codable, Equatable {
    var start: Date
    var end: Date?
}

@Model
final class Session {
    var id: UUID = UUID()
    var project: Project?
    var date: Date = Date.now
    var startTime: Date = Date.now
    var endTime: Date?
    var durationSeconds: TimeInterval = 0
    var workPeriodsData: Data? = nil
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

    /// A ausência do campo mantém registros legados legíveis sem regravá-los.
    var workPeriods: [SessionWorkPeriod] {
        get {
            if let workPeriodsData,
               let periods = try? JSONDecoder().decode([SessionWorkPeriod].self, from: workPeriodsData),
               !periods.isEmpty {
                return periods
            }
            if status == .running {
                return [SessionWorkPeriod(start: startTime, end: nil)]
            }
            let end = endTime ?? startTime.addingTimeInterval(max(0, durationSeconds))
            // Legados inconsistentes com duração positiva preservam o total salvo.
            // Zero pode ser um valor não inicializado: conserva o intervalo original.
            let legacyStart = durationSeconds > 0 && abs(end.timeIntervalSince(startTime) - durationSeconds) > 0.001
                ? end.addingTimeInterval(-durationSeconds) : startTime
            return [SessionWorkPeriod(start: legacyStart, end: end)]
        }
        set { workPeriodsData = try? JSONEncoder().encode(newValue) }
    }

    /// Recência de trabalho, independente de alterações posteriores na observação.
    var latestActivity: Date {
        workPeriods.map { $0.end ?? $0.start }.max() ?? startTime
    }

    /// Total exibido pelo timer: trabalho já fechado mais o trecho corrente.
    func elapsedDuration(at now: Date = .now) -> TimeInterval {
        guard status == .running else { return durationSeconds }
        return durationSeconds + workPeriods.filter { $0.end == nil }.reduce(0) {
            $0 + max(0, now.timeIntervalSince($1.start))
        }
    }

    /// Trabalho dentro do período, incluindo o trecho aberto até `asOf`.
    func workedDuration(in interval: DateInterval, asOf: Date = .now) -> TimeInterval {
        workPeriods.reduce(0) { total, period in
            let start = max(period.start, interval.start)
            let end = min(period.end ?? asOf, interval.end)
            return total + max(0, end.timeIntervalSince(start))
        }
    }

    /// Valor estimado da sessão com base no "Valor por dia" do projeto,
    /// assumindo uma jornada padrão de `Project.standardWorkdayHours`.
    var estimatedValue: Decimal {
        guard let dailyRate = project?.dailyRate, dailyRate > 0 else { return 0 }
        let hoursWorked = durationSeconds / 3600
        return dailyRate * Decimal(hoursWorked / Project.standardWorkdayHours)
    }
}
