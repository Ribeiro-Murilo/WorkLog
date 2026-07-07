import Testing
import Foundation
@testable import WorkLog

@MainActor
struct BillingViewModelTests {
    private func makeSession(project: Project, date: Date, durationSeconds: TimeInterval, status: SessionStatus = .completed) -> Session {
        Session(
            project: project,
            date: date,
            startTime: date,
            endTime: date.addingTimeInterval(durationSeconds),
            durationSeconds: durationSeconds,
            category: .work,
            status: status
        )
    }

    @Test func previewOnlyIncludesSelectedClientAndClosedSessions() throws {
        let context = makeInMemoryContext()
        let projectRepository = ProjectRepository(modelContext: context)
        let sessionRepository = SessionRepository(modelContext: context)

        let acmeProject = Project(name: "Site", client: "Acme", dailyRate: 800, category: .work)
        let otherProject = Project(name: "App", client: "Other", dailyRate: 800, category: .work)
        try projectRepository.insert(acmeProject)
        try projectRepository.insert(otherProject)

        let today = Date.now
        try sessionRepository.insert(makeSession(project: acmeProject, date: today, durationSeconds: 3600))
        try sessionRepository.insert(makeSession(project: otherProject, date: today, durationSeconds: 3600))
        try sessionRepository.insert(makeSession(project: acmeProject, date: today, durationSeconds: 1800, status: .running))

        let vm = BillingViewModel(
            projectRepository: projectRepository,
            sessionRepository: sessionRepository,
            invoiceRepository: InvoiceRepository(modelContext: context, settingsRepository: SettingsRepository(modelContext: context)),
            settingsRepository: SettingsRepository(modelContext: context),
            exportService: ExportService()
        )
        vm.period = .today
        vm.selectedClient = "Acme"

        #expect(vm.previewLineItems.count == 1)
        #expect(vm.previewLineItems[0].durationSeconds == 3600)
    }

    @Test func generateInvoicePersistsWithSequentialNumberAndFreezesLineItems() throws {
        let context = makeInMemoryContext()
        let projectRepository = ProjectRepository(modelContext: context)
        let sessionRepository = SessionRepository(modelContext: context)
        let invoiceRepository = InvoiceRepository(modelContext: context, settingsRepository: SettingsRepository(modelContext: context))

        let project = Project(name: "Site", client: "Acme", dailyRate: 800, category: .work)
        try projectRepository.insert(project)
        try sessionRepository.insert(makeSession(project: project, date: .now, durationSeconds: 3600))

        let vm = BillingViewModel(
            projectRepository: projectRepository,
            sessionRepository: sessionRepository,
            invoiceRepository: invoiceRepository,
            settingsRepository: SettingsRepository(modelContext: context),
            exportService: ExportService()
        )
        vm.period = .today
        vm.selectedClient = "Acme"
        #expect(!vm.previewLineItems.isEmpty)

        vm.generateInvoice()

        #expect(vm.invoices.count == 1)
        #expect(vm.invoices[0].number == 1)
        #expect(vm.invoices[0].status == .pending)
        #expect(vm.invoices[0].lineItems.count == 1)

        try projectRepository.delete(project)

        #expect(vm.invoices[0].lineItems.count == 1)
    }

    @Test func generateInvoiceRejectsOverlappingPeriodForSameClient() throws {
        let context = makeInMemoryContext()
        let projectRepository = ProjectRepository(modelContext: context)
        let sessionRepository = SessionRepository(modelContext: context)
        let invoiceRepository = InvoiceRepository(modelContext: context, settingsRepository: SettingsRepository(modelContext: context))

        let project = Project(name: "Site", client: "Acme", dailyRate: 800, category: .work)
        try projectRepository.insert(project)
        let today = Date.now
        try sessionRepository.insert(makeSession(project: project, date: today, durationSeconds: 3600))

        let vm = BillingViewModel(
            projectRepository: projectRepository,
            sessionRepository: sessionRepository,
            invoiceRepository: invoiceRepository,
            settingsRepository: SettingsRepository(modelContext: context),
            exportService: ExportService()
        )
        vm.period = .today
        vm.selectedClient = "Acme"
        vm.generateInvoice()
        #expect(vm.invoices.count == 1)

        // Mesmo período novamente: deve ser rejeitado por sobreposição.
        vm.generateInvoice()

        #expect(vm.invoices.count == 1)
        #expect(vm.errorMessage != nil)
    }

    @Test func generateInvoiceDoesNothingWithoutSessions() throws {
        let context = makeInMemoryContext()
        let projectRepository = ProjectRepository(modelContext: context)
        let project = Project(name: "Site", client: "Acme", dailyRate: 800, category: .work)
        try projectRepository.insert(project)

        let vm = BillingViewModel(
            projectRepository: projectRepository,
            sessionRepository: SessionRepository(modelContext: context),
            invoiceRepository: InvoiceRepository(modelContext: context, settingsRepository: SettingsRepository(modelContext: context)),
            settingsRepository: SettingsRepository(modelContext: context),
            exportService: ExportService()
        )
        vm.selectedClient = "Acme"

        vm.generateInvoice()

        #expect(vm.invoices.isEmpty)
    }
}
