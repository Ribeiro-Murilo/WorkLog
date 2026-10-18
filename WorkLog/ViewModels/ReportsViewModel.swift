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

    /// Resolve o período em um `DateInterval` concreto a partir de uma data de referência.
    func dateInterval(customStart: Date, customEnd: Date, referenceDate: Date = .now) -> DateInterval {
        let calendar = Calendar.current
        switch self {
        case .today:
            return calendar.dateInterval(of: .day, for: referenceDate) ?? DateInterval(start: referenceDate, end: referenceDate)
        case .yesterday:
            let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceDate) ?? referenceDate
            return calendar.dateInterval(of: .day, for: yesterday) ?? DateInterval(start: yesterday, end: yesterday)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: referenceDate) ?? DateInterval(start: referenceDate, end: referenceDate)
        case .month:
            return calendar.dateInterval(of: .month, for: referenceDate) ?? DateInterval(start: referenceDate, end: referenceDate)
        case .year:
            return calendar.dateInterval(of: .year, for: referenceDate) ?? DateInterval(start: referenceDate, end: referenceDate)
        case .custom:
            return DateInterval(start: customStart, end: customEnd)
        }
    }
}

@MainActor
@Observable
final class ReportsViewModel {
    private let sessionRepository: SessionRepositoryProtocol
    private let exportService: ExportServiceProtocol
    private let presetRepository: ReportPresetRepositoryProtocol?
    private let settingsRepository: SettingsRepositoryProtocol?

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

    /// Colunas escolhidas para o relatório, na ordem em que devem aparecer.
    var selectedColumns: [ReportColumn] = ReportColumn.defaultSelection
    /// Modo de consolidação das sessões.
    var grouping: ReportGrouping = .detailed

    private(set) var sessions: [Session] = []
    private(set) var presets: [ReportPreset] = []
    var errorMessage: String?

    init(
        sessionRepository: SessionRepositoryProtocol,
        exportService: ExportServiceProtocol,
        presetRepository: ReportPresetRepositoryProtocol? = nil,
        settingsRepository: SettingsRepositoryProtocol? = nil
    ) {
        self.sessionRepository = sessionRepository
        self.exportService = exportService
        self.presetRepository = presetRepository
        self.settingsRepository = settingsRepository
        loadPresets()
        generate()
    }

    func generate() {
        do {
            let interval = period.dateInterval(customStart: customStart, customEnd: customEnd)
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

    var totalDuration: TimeInterval { detailedRows.reduce(0) { $0 + $1.durationSeconds } }

    var totalValue: Decimal { detailedRows.reduce(Decimal(0)) { $0 + $1.estimatedValue } }

    private var detailedRows: [ReportRow] {
        let interval = period.dateInterval(customStart: customStart, customEnd: customEnd)
        return sessions.flatMap { $0.recordedReportRows(in: interval) }
    }

    // MARK: - Colunas

    func isColumnSelected(_ column: ReportColumn) -> Bool {
        selectedColumns.contains(column)
    }

    /// Alterna uma coluna preservando a ordem canônica de `ReportColumn.allCases`.
    func toggleColumn(_ column: ReportColumn) {
        if selectedColumns.contains(column) {
            selectedColumns.removeAll { $0 == column }
        } else {
            selectedColumns = ReportColumn.allCases.filter { selectedColumns.contains($0) || $0 == column }
        }
    }

    // MARK: - Linhas do relatório

    /// Converte as sessões filtradas em linhas, aplicando o modo de agrupamento.
    func reportRows() -> [ReportRow] {
        switch grouping {
        case .detailed:
            return detailedRows
        case .byProjectAndDay:
            return groupedByProjectAndDay()
        }
    }

    private func groupedByProjectAndDay() -> [ReportRow] {
        let calendar = Calendar.current
        var order: [String] = []
        var buckets: [String: [ReportRow]] = [:]
        // As linhas derivadas podem ser vários trechos da mesma sessão no mesmo dia.
        let projectIDs = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id.uuidString, $0.project?.id.uuidString ?? "—") })
        for row in detailedRows {
            let sessionID = String(row.id.split(separator: "#")[0])
            let day = calendar.startOfDay(for: row.date)
            let key = "\(projectIDs[sessionID] ?? "—")#\(day.timeIntervalSinceReferenceDate)"
            if buckets[key] == nil { buckets[key] = []; order.append(key) }
            buckets[key]?.append(row)
        }
        return order.compactMap { key -> ReportRow? in
            guard let group = buckets[key], let first = group.first else { return nil }
            let sessionIDs = Set(group.map { String($0.id.split(separator: "#")[0]) })
            var seenNotes = Set<String>()
            let notes = group.filter { seenNotes.insert(String($0.id.split(separator: "#")[0])).inserted }
                .map(\.note).filter { !$0.isEmpty }.joined(separator: " | ")
            return ReportRow(id: key, projectName: first.projectName, client: first.client,
                date: first.date, startTime: group.map(\.startTime).min() ?? first.startTime,
                endTime: group.compactMap(\.endTime).max(),
                durationSeconds: group.reduce(0) { $0 + $1.durationSeconds },
                category: first.category, status: first.status,
                estimatedValue: group.reduce(Decimal(0)) { $0 + $1.estimatedValue }, note: notes,
                tags: first.tags, descriptionText: first.descriptionText, sessionCount: sessionIDs.count)
        }
    }

    func exportTable() -> ExportTable {
        let columns = selectedColumns.isEmpty ? ReportColumn.defaultSelection : selectedColumns
        let headers = columns.map(\.header)
        let rows = reportRows().map { row in
            columns.map { $0.value(from: row) }
        }
        return ExportTable(
            title: "Relatório — \(period.displayName)",
            headers: headers,
            rows: rows,
            alignments: columns.map(\.pdfAlignment),
            weights: columns.map(\.pdfWeight)
        )
    }

    func export(format: ExportFormat, to url: URL) throws {
        let includeLogo = (try? settingsRepository?.current().includeLogoInPDF) ?? false
        try exportService.export(exportTable(), format: format, to: url, includeLogo: includeLogo)
    }

    // MARK: - Presets

    func loadPresets() {
        guard let presetRepository else { return }
        do {
            presets = try presetRepository.fetchAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveCurrentAsPreset(name: String) {
        guard let presetRepository else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            if let existing = presets.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                existing.name = trimmed
                existing.columnsRaw = selectedColumns.map(\.rawValue)
                existing.groupingRaw = grouping.rawValue
                existing.updatedAt = .now
                try presetRepository.save()
            } else {
                let preset = ReportPreset(name: trimmed, columns: selectedColumns, grouping: grouping)
                try presetRepository.insert(preset)
            }
            loadPresets()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applyPreset(_ preset: ReportPreset) {
        let columns = preset.columns
        selectedColumns = columns.isEmpty ? ReportColumn.defaultSelection : columns
        grouping = preset.grouping
        generate()
    }

    func deletePreset(_ preset: ReportPreset) {
        guard let presetRepository else { return }
        do {
            try presetRepository.delete(preset)
            loadPresets()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    #if DEBUG
    func setSessionsForTesting(_ value: [Session]) {
        sessions = value
    }
    #endif
}
