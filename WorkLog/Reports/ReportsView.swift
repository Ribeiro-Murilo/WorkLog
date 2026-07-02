import SwiftUI
import AppKit

struct ReportsView: View {
    @Environment(\.dependencies) private var dependencies
    @State private var viewModel: ReportsViewModel?
    @State private var allProjects: [Project] = []
    @State private var exportErrorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let viewModel {
                filtersBar(viewModel)
                Divider()
                sessionsTable(viewModel)
                Divider()
                footer(viewModel)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Relatórios")
        .alert(
            "Erro ao exportar",
            isPresented: Binding(get: { exportErrorMessage != nil }, set: { if !$0 { exportErrorMessage = nil } })
        ) {
            Button("OK", role: .cancel) { exportErrorMessage = nil }
        } message: {
            Text(exportErrorMessage ?? "")
        }
        .task { setup() }
    }

    private func filtersBar(_ viewModel: ReportsViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("Período", selection: Binding(get: { viewModel.period }, set: { viewModel.period = $0 })) {
                    ForEach(ReportPeriod.allCases) { period in
                        Text(period.displayName).tag(period)
                    }
                }
                .frame(maxWidth: 220)

                if viewModel.period == .custom {
                    DatePicker("De", selection: Binding(get: { viewModel.customStart }, set: {
                        viewModel.customStart = $0
                        viewModel.generate()
                    }), displayedComponents: .date)
                    DatePicker("Até", selection: Binding(get: { viewModel.customEnd }, set: {
                        viewModel.customEnd = $0
                        viewModel.generate()
                    }), displayedComponents: .date)
                }

                Spacer()
            }

            HStack {
                Picker("Projeto", selection: Binding(get: { viewModel.projectFilter }, set: { viewModel.projectFilter = $0 })) {
                    Text("Todos os projetos").tag(Project?.none)
                    ForEach(allProjects) { project in
                        Text(project.name).tag(Project?.some(project))
                    }
                }
                .frame(maxWidth: 200)

                Picker("Categoria", selection: Binding(get: { viewModel.categoryFilter }, set: { viewModel.categoryFilter = $0 })) {
                    Text("Todas").tag(ProjectCategory?.none)
                    ForEach(ProjectCategory.allCases) { category in
                        Text(category.displayName).tag(ProjectCategory?.some(category))
                    }
                }
                .frame(maxWidth: 160)

                Picker("Status", selection: Binding(get: { viewModel.statusFilter }, set: { viewModel.statusFilter = $0 })) {
                    Text("Todos").tag(SessionStatus?.none)
                    ForEach(SessionStatus.allCases) { status in
                        Text(status.displayName).tag(SessionStatus?.some(status))
                    }
                }
                .frame(maxWidth: 160)

                TextField("Cliente", text: Binding(
                    get: { viewModel.clientFilter ?? "" },
                    set: { viewModel.clientFilter = $0.isEmpty ? nil : $0 }
                ))
                .frame(maxWidth: 140)

                TextField("Tag", text: Binding(
                    get: { viewModel.tagFilter ?? "" },
                    set: { viewModel.tagFilter = $0.isEmpty ? nil : $0 }
                ))
                .frame(maxWidth: 120)

                Spacer()
            }
        }
        .padding(16)
    }

    private func sessionsTable(_ viewModel: ReportsViewModel) -> some View {
        Table(viewModel.sessions) {
            TableColumn("Projeto") { session in
                Text(session.project?.name ?? "—")
            }
            TableColumn("Cliente") { session in
                Text(session.project?.client ?? "—")
            }
            TableColumn("Data") { session in
                Text(DateFormatter.shortDate.string(from: session.date))
            }
            TableColumn("Início") { session in
                Text(DateFormatter.shortTime.string(from: session.startTime))
            }
            TableColumn("Fim") { session in
                Text(session.endTime.map { DateFormatter.shortTime.string(from: $0) } ?? "—")
            }
            TableColumn("Duração") { session in
                Text(session.durationSeconds.formattedClock(showSeconds: true))
                    .monospacedDigit()
            }
            TableColumn("Categoria") { session in
                Text(session.category.displayName)
            }
            TableColumn("Status") { session in
                Text(session.status.displayName)
            }
            TableColumn("Valor") { session in
                Text(session.estimatedValue.currencyFormatted)
                    .monospacedDigit()
            }
        }
        .overlay {
            if viewModel.sessions.isEmpty {
                ContentUnavailableView(
                    "Nenhuma sessão no período",
                    systemImage: "chart.bar.doc.horizontal",
                    description: Text("Ajuste os filtros para visualizar sessões registradas.")
                )
            }
        }
    }

    private func footer(_ viewModel: ReportsViewModel) -> some View {
        HStack {
            let total = viewModel.sessions.reduce(0) { $0 + $1.durationSeconds }
            Text("Total: \(total.formattedClock(showSeconds: false))")
                .font(.headline)
                .monospacedDigit()

            Text("Valor: \(viewModel.totalValue.currencyFormatted)")
                .font(.headline)
                .monospacedDigit()

            Spacer()

            ForEach(ExportFormat.allCases) { format in
                Button(format.displayName) {
                    export(viewModel, format: format)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
    }

    private func export(_ viewModel: ReportsViewModel, format: ExportFormat) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Relatorio.\(format.fileExtension)"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try viewModel.export(format: format, to: url)
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }

    private func setup() {
        if viewModel == nil {
            viewModel = ReportsViewModel(
                sessionRepository: dependencies.sessionRepository,
                exportService: dependencies.exportService
            )
        }
        allProjects = (try? dependencies.projectRepository.fetchAll(includeArchived: true)) ?? []
    }
}
