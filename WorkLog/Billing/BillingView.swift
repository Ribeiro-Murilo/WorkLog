import SwiftUI
import AppKit

struct BillingView: View {
    @Environment(\.dependencies) private var dependencies
    @State private var viewModel: BillingViewModel?
    @State private var exportErrorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let viewModel {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        generatorSection(viewModel)
                        Divider()
                        historySection(viewModel)
                    }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Faturamento")
        .alert(
            "Erro",
            isPresented: Binding(get: { exportErrorMessage != nil }, set: { if !$0 { exportErrorMessage = nil } })
        ) {
            Button("OK", role: .cancel) { exportErrorMessage = nil }
        } message: {
            Text(exportErrorMessage ?? "")
        }
        .task { setup() }
    }

    private func generatorSection(_ viewModel: BillingViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nova fatura")
                .font(.headline)

            HStack {
                Picker("Cliente", selection: Binding(get: { viewModel.selectedClient }, set: { viewModel.selectedClient = $0 })) {
                    ForEach(viewModel.availableClients, id: \.self) { client in
                        Text(client).tag(String?.some(client))
                    }
                }
                .frame(maxWidth: 220)

                Picker("Período", selection: Binding(get: { viewModel.period }, set: { viewModel.period = $0 })) {
                    ForEach(ReportPeriod.allCases) { period in
                        Text(period.displayName).tag(period)
                    }
                }
                .frame(maxWidth: 200)

                if viewModel.period == .custom {
                    DatePicker("De", selection: Binding(get: { viewModel.customStart }, set: {
                        viewModel.customStart = $0
                        viewModel.generatePreview()
                    }), displayedComponents: .date)
                    DatePicker("Até", selection: Binding(get: { viewModel.customEnd }, set: {
                        viewModel.customEnd = $0
                        viewModel.generatePreview()
                    }), displayedComponents: .date)
                }

                Spacer()
            }

            Table(viewModel.previewLineItems) {
                TableColumn("Data") { item in
                    Text(DateFormatter.shortDate.string(from: item.date))
                }
                TableColumn("Projeto") { item in
                    Text(item.projectName)
                }
                TableColumn("Duração") { item in
                    Text(item.durationSeconds.formattedClock(showSeconds: false)).monospacedDigit()
                }
                TableColumn("Valor") { item in
                    Text(item.value.currencyFormatted).monospacedDigit()
                }
            }
            .frame(minHeight: 140, idealHeight: 180, maxHeight: 220)
            .overlay {
                if viewModel.previewLineItems.isEmpty {
                    ContentUnavailableView(
                        "Nenhuma sessão no período",
                        systemImage: "doc.text",
                        description: Text("Selecione um cliente e período com sessões encerradas.")
                    )
                }
            }

            if viewModel.periodOverlapsExistingInvoice {
                Label("Já existe uma fatura deste cliente com período sobreposto a este.", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            HStack {
                Text("Total: \(viewModel.previewTotalDuration.formattedClock(showSeconds: false))")
                    .font(.headline)
                    .monospacedDigit()
                Text("Valor: \(viewModel.previewTotalValue.currencyFormatted)")
                    .font(.headline)
                    .monospacedDigit()

                Spacer()

                TextField("Observações (opcional)", text: Binding(get: { viewModel.notes }, set: { viewModel.notes = $0 }))
                    .frame(maxWidth: 240)

                Button("Gerar fatura") {
                    viewModel.generateInvoice()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.previewLineItems.isEmpty || viewModel.periodOverlapsExistingInvoice)
            }
        }
        .padding(16)
    }

    private func historySection(_ viewModel: BillingViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Histórico")
                .font(.headline)

            Table(viewModel.invoices) {
                TableColumn("Nº") { invoice in
                    Text(invoice.formattedNumber)
                }
                TableColumn("Cliente") { invoice in
                    Text(invoice.client)
                }
                TableColumn("Período") { invoice in
                    Text("\(DateFormatter.shortDate.string(from: invoice.periodStart)) – \(DateFormatter.shortDate.string(from: invoice.periodEnd))")
                }
                TableColumn("Valor") { invoice in
                    Text(invoice.totalValue.currencyFormatted).monospacedDigit()
                }
                TableColumn("Status") { invoice in
                    Button(invoice.status.displayName) {
                        viewModel.toggleStatus(invoice)
                    }
                    .buttonStyle(.bordered)
                    .tint(invoice.status == .paid ? .green : .orange)
                }
                TableColumn("Ações") { invoice in
                    HStack(spacing: 8) {
                        Button {
                            exportInvoice(invoice, viewModel: viewModel)
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        Button(role: .destructive) {
                            viewModel.delete(invoice)
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
            .frame(minHeight: 160, idealHeight: 220)
            .overlay {
                if viewModel.invoices.isEmpty {
                    ContentUnavailableView(
                        "Nenhuma fatura emitida",
                        systemImage: "doc.text",
                        description: Text("Gere uma fatura acima para vê-la aqui.")
                    )
                }
            }
        }
        .padding(16)
    }

    private func exportInvoice(_ invoice: Invoice, viewModel: BillingViewModel) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(invoice.formattedNumber).pdf"
        panel.canCreateDirectories = true

        // App acessório (`LSUIElement`): sem ativar a app e elevar o painel, o
        // `NSSavePanel` abre sem foco/janela chave e dispara uma asserção do AppKit.
        NSApp.activate(ignoringOtherApps: true)
        panel.level = .modalPanel
        panel.makeKeyAndOrderFront(nil)

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try viewModel.export(invoice, to: url)
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }

    private func setup() {
        if viewModel == nil {
            viewModel = BillingViewModel(
                projectRepository: dependencies.projectRepository,
                sessionRepository: dependencies.sessionRepository,
                invoiceRepository: dependencies.invoiceRepository,
                settingsRepository: dependencies.settingsRepository,
                exportService: dependencies.exportService
            )
        }
    }
}
