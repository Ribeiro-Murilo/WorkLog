import SwiftUI
import AppKit

struct ReportsView: View {
    @Environment(\.dependencies) private var dependencies
    @State private var viewModel: ReportsViewModel?
    @State private var allProjects: [Project] = []
    @State private var exportErrorMessage: String?
    @State private var isPresentingSavePreset = false
    @State private var newPresetName = ""
    @State private var isShowingColumns = false

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
        .alert("Salvar tipo de relatório", isPresented: $isPresentingSavePreset) {
            TextField("Nome", text: $newPresetName)
            Button("Salvar") {
                viewModel?.saveCurrentAsPreset(name: newPresetName)
                newPresetName = ""
            }
            Button("Cancelar", role: .cancel) { newPresetName = "" }
        } message: {
            Text("As colunas e o agrupamento atuais serão salvos com este nome.")
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

            configBar(viewModel)
        }
        .padding(16)
    }

    private func configBar(_ viewModel: ReportsViewModel) -> some View {
        HStack {
            Picker("Agrupamento", selection: Binding(
                get: { viewModel.grouping },
                set: { viewModel.grouping = $0 }
            )) {
                ForEach(ReportGrouping.allCases) { grouping in
                    Text(grouping.displayName).tag(grouping)
                }
            }
            .frame(maxWidth: 260)

            Button {
                isShowingColumns.toggle()
            } label: {
                Label("Colunas", systemImage: "chevron.down")
                    .labelStyle(.titleAndIcon)
            }
            .popover(isPresented: $isShowingColumns, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Colunas do relatório")
                        .font(.headline)
                    ForEach(ReportColumn.allCases) { column in
                        Toggle(column.header, isOn: Binding(
                            get: { viewModel.isColumnSelected(column) },
                            set: { _ in viewModel.toggleColumn(column) }
                        ))
                        .toggleStyle(.checkbox)
                    }
                }
                .padding(16)
                .frame(minWidth: 200, alignment: .leading)
            }

            Divider().frame(height: 18)

            Picker("Tipo salvo", selection: Binding<ReportPreset?>(
                get: { nil },
                set: { if let preset = $0 { viewModel.applyPreset(preset) } }
            )) {
                Text("Selecionar…").tag(ReportPreset?.none)
                ForEach(viewModel.presets) { preset in
                    Text(preset.name).tag(ReportPreset?.some(preset))
                }
            }
            .frame(maxWidth: 200)

            Button("Salvar tipo…") {
                isPresentingSavePreset = true
            }
            .buttonStyle(.bordered)

            Menu {
                if viewModel.presets.isEmpty {
                    Text("Nenhum tipo salvo")
                } else {
                    ForEach(viewModel.presets) { preset in
                        Button("Excluir \(preset.name)", role: .destructive) {
                            viewModel.deletePreset(preset)
                        }
                    }
                }
            } label: {
                Image(systemName: "trash")
            }
            .frame(maxWidth: 60)

            Spacer()
        }
    }

    private func sessionsTable(_ viewModel: ReportsViewModel) -> some View {
        let rows = viewModel.reportRows()
        let columns = viewModel.selectedColumns.isEmpty ? ReportColumn.defaultSelection : viewModel.selectedColumns
        return Table(rows) {
            TableColumnForEach(columns) { column in
                TableColumn(column.header) { row in
                    Text(column.value(from: row))
                        .monospacedDigit()
                }
            }
        }
        .overlay {
            if rows.isEmpty {
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

        // App acessório (`LSUIElement`): sem ativar a app e elevar o painel, o
        // `NSSavePanel` abre sem foco/janela chave e dispara uma asserção do
        // AppKit (EXC_BREAKPOINT). Ativar antes torna a exportação confiável.
        NSApp.activate(ignoringOtherApps: true)
        panel.level = .modalPanel
        panel.makeKeyAndOrderFront(nil)

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
                exportService: dependencies.exportService,
                presetRepository: dependencies.reportPresetRepository,
                settingsRepository: dependencies.settingsRepository
            )
        }
        allProjects = (try? dependencies.projectRepository.fetchAll(includeArchived: true)) ?? []
    }
}
