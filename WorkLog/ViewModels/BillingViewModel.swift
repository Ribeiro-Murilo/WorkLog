import Foundation
import Observation

@MainActor
@Observable
final class BillingViewModel {
    private let projectRepository: ProjectRepositoryProtocol
    private let sessionRepository: SessionRepositoryProtocol
    private let invoiceRepository: InvoiceRepositoryProtocol
    private let settingsRepository: SettingsRepositoryProtocol
    private let exportService: ExportServiceProtocol

    var period: ReportPeriod = .month {
        didSet { generatePreview() }
    }
    var customStart: Date = .now
    var customEnd: Date = .now
    var selectedClient: String? {
        didSet { generatePreview() }
    }
    var notes: String = ""

    private(set) var availableClients: [String] = []
    private(set) var previewLineItems: [InvoiceLineItem] = []
    private(set) var invoices: [Invoice] = []
    var errorMessage: String?

    init(
        projectRepository: ProjectRepositoryProtocol,
        sessionRepository: SessionRepositoryProtocol,
        invoiceRepository: InvoiceRepositoryProtocol,
        settingsRepository: SettingsRepositoryProtocol,
        exportService: ExportServiceProtocol
    ) {
        self.projectRepository = projectRepository
        self.sessionRepository = sessionRepository
        self.invoiceRepository = invoiceRepository
        self.settingsRepository = settingsRepository
        self.exportService = exportService
        loadClients()
        loadInvoices()
        generatePreview()
    }

    var previewTotalValue: Decimal {
        previewLineItems.reduce(Decimal(0)) { $0 + $1.value }
    }

    var previewTotalDuration: TimeInterval {
        previewLineItems.reduce(0) { $0 + $1.durationSeconds }
    }

    func loadClients() {
        do {
            let projects = try projectRepository.fetchAll(includeArchived: true)
            availableClients = Array(Set(projects.map(\.client))).sorted()
            if selectedClient == nil {
                selectedClient = availableClients.first
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadInvoices() {
        do {
            invoices = try invoiceRepository.fetchAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func generatePreview() {
        guard let client = selectedClient else {
            previewLineItems = []
            return
        }
        do {
            let interval = period.dateInterval(customStart: customStart, customEnd: customEnd)
            let closedStatuses: Set<SessionStatus> = [.completed, .paused]
            let sessions = try sessionRepository.fetchSessions(in: interval)
                .filter { $0.project?.client == client && closedStatuses.contains($0.status) }
            previewLineItems = Self.groupByProjectAndDay(sessions)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Consolida sessões por projeto e dia, igual ao agrupamento usado nos Relatórios.
    private static func groupByProjectAndDay(_ sessions: [Session]) -> [InvoiceLineItem] {
        let calendar = Calendar.current
        var order: [String] = []
        var buckets: [String: [Session]] = [:]

        for session in sessions {
            let day = calendar.startOfDay(for: session.date)
            let projectKey = session.project?.id.uuidString ?? "—"
            let key = "\(projectKey)#\(day.timeIntervalSinceReferenceDate)"
            if buckets[key] == nil {
                buckets[key] = []
                order.append(key)
            }
            buckets[key]?.append(session)
        }

        return order.compactMap { key -> InvoiceLineItem? in
            guard let group = buckets[key], let first = group.first else { return nil }
            let duration = group.reduce(0) { $0 + $1.durationSeconds }
            let value = group.reduce(Decimal(0)) { $0 + $1.estimatedValue }
            return InvoiceLineItem(
                date: calendar.startOfDay(for: first.date),
                projectName: first.project?.name ?? "—",
                durationSeconds: duration,
                value: value
            )
        }.sorted { $0.date < $1.date }
    }

    /// Período/cliente atuais já têm uma fatura emitida com intervalo sobreposto.
    var periodOverlapsExistingInvoice: Bool {
        guard let client = selectedClient else { return false }
        let interval = period.dateInterval(customStart: customStart, customEnd: customEnd)
        return (try? invoiceRepository.hasOverlap(client: client, start: interval.start, end: interval.end, excluding: nil)) ?? false
    }

    func generateInvoice() {
        guard let client = selectedClient, !previewLineItems.isEmpty else { return }
        do {
            let interval = period.dateInterval(customStart: customStart, customEnd: customEnd)
            guard try !invoiceRepository.hasOverlap(client: client, start: interval.start, end: interval.end, excluding: nil) else {
                errorMessage = "Já existe uma fatura para \(client) com período sobreposto a este."
                return
            }
            let number = try invoiceRepository.nextNumber()
            let invoice = Invoice(
                number: number,
                client: client,
                periodStart: interval.start,
                periodEnd: interval.end,
                lineItems: previewLineItems,
                notes: notes
            )
            try invoiceRepository.insert(invoice)
            notes = ""
            loadInvoices()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleStatus(_ invoice: Invoice) {
        invoice.status = invoice.status == .pending ? .paid : .pending
        do {
            try invoiceRepository.update(invoice)
        } catch {
            errorMessage = error.localizedDescription
        }
        loadInvoices()
    }

    func delete(_ invoice: Invoice) {
        do {
            try invoiceRepository.delete(invoice)
        } catch {
            errorMessage = error.localizedDescription
        }
        loadInvoices()
    }

    func export(_ invoice: Invoice, to url: URL) throws {
        let settings = try settingsRepository.current()
        let document = InvoiceDocument(
            issuerName: settings.invoiceIssuerName,
            issuerDetails: settings.invoiceIssuerDetails,
            invoiceNumber: invoice.formattedNumber,
            issueDate: invoice.issueDate,
            client: invoice.client,
            periodStart: invoice.periodStart,
            periodEnd: invoice.periodEnd,
            lineItems: invoice.lineItems,
            totalDurationSeconds: invoice.totalDurationSeconds,
            totalValue: invoice.totalValue,
            notes: invoice.notes
        )
        try exportService.exportInvoice(document, to: url)
    }

    #if DEBUG
    func setPreviewLineItemsForTesting(_ value: [InvoiceLineItem]) {
        previewLineItems = value
    }
    #endif
}
