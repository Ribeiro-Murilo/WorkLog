import Foundation
import Observation

enum ReportPeriod: String, CaseIterable, Identifiable {
    case today
    case yesterday
    case week
    case month
    case year
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .today: return "Hoje"
        case .yesterday: return "Ontem"
        case .week: return "Semana"
        case .month: return "Mês"
        case .year: return "Ano"
        case .custom: return "Período personalizado"
        }
    }
}

@MainActor
@Observable
final class ReportsViewModel {
    private let sessionRepository: SessionRepositoryProtocol
    private let exportService: ExportServiceProtocol

    var period: ReportPeriod = .today {
        didSet { generate() }
    }
    var customStart: Date = .now
    var customEnd: Date = .now
    var projectFilter: Project? {
        didSet { generate() }
    }
    var clientFilter: String? {
        didSet { generate() }
    }
    var categoryFilter: ProjectCategory? {
        didSet { generate() }
    }
    var statusFilter: SessionStatus? {
        didSet { generate() }
    }
    var tagFilter: String? {
        didSet { generate() }
    }

    private(set) var sessions: [Session] = []
    var errorMessage: String?

    init(sessionRepository: SessionRepositoryProtocol, exportService: ExportServiceProtocol) {
        self.sessionRepository = sessionRepository
        self.exportService = exportService
        generate()
    }

    func generate() {
        do {
            let interval = dateInterval(for: period)
            var results = try sessionRepository.fetchSessions(in: interval)

            if let projectFilter {
                results = results.filter { $0.project?.id == projectFilter.id }
            }
            if let clientFilter {
                results = results.filter { $0.project?.client == clientFilter }
            }
            if let categoryFilter {
                results = results.filter { $0.category == categoryFilter }
            }
            if let statusFilter {
                results = results.filter { $0.status == statusFilter }
            }
            if let tagFilter {
                results = results.filter { $0.project?.tags.contains(tagFilter) ?? false }
            }
            sessions = results
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func dateInterval(for period: ReportPeriod) -> DateInterval {
        let calendar = Calendar.current
        let now = Date.now

        switch period {
        case .today:
            return calendar.dateInterval(of: .day, for: now) ?? DateInterval(start: now, end: now)
        case .yesterday:
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
            return calendar.dateInterval(of: .day, for: yesterday) ?? DateInterval(start: yesterday, end: yesterday)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: now) ?? DateInterval(start: now, end: now)
        case .month:
            return calendar.dateInterval(of: .month, for: now) ?? DateInterval(start: now, end: now)
        case .year:
            return calendar.dateInterval(of: .year, for: now) ?? DateInterval(start: now, end: now)
        case .custom:
            return DateInterval(start: customStart, end: customEnd)
        }
    }

    var totalValue: Decimal {
        sessions.reduce(Decimal(0)) { $0 + $1.estimatedValue }
    }

    func exportTable() -> ExportTable {
        let headers = ["Projeto", "Cliente", "Data", "Início", "Fim", "Duração", "Categoria", "Status", "Valor", "Observação"]
        let rows = sessions.map { session -> [String] in
            [
                session.project?.name ?? "—",
                session.project?.client ?? "—",
                DateFormatter.shortDate.string(from: session.date),
                DateFormatter.shortTime.string(from: session.startTime),
                session.endTime.map { DateFormatter.shortTime.string(from: $0) } ?? "—",
                session.durationSeconds.formattedClock(showSeconds: true),
                session.category.displayName,
                session.status.displayName,
                session.estimatedValue.currencyFormatted,
                session.note,
            ]
        }
        return ExportTable(title: "Relatório — \(period.displayName)", headers: headers, rows: rows)
    }

    func export(format: ExportFormat, to url: URL) throws {
        try exportService.export(exportTable(), format: format, to: url)
    }
}
