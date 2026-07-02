import SwiftUI

struct ProjectDetailView: View {
    @Environment(\.dependencies) private var dependencies
    let project: Project
    var onProjectChanged: (() -> Void)?

    @State private var viewModel: ProjectDetailViewModel?
    @State private var showingEditForm = false
    @State private var showingNewSessionForm = false
    @State private var sessionPendingEdit: Session?
    @State private var sessionPendingDeletion: Session?

    var body: some View {
        ScrollView {
            if let viewModel {
                VStack(alignment: .leading, spacing: 20) {
                    header(viewModel)
                    Divider()
                    timerSection(viewModel)
                    Divider()
                    sessionsSection(viewModel)
                }
                .padding(20)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(project.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingEditForm = true
                } label: {
                    Label("Editar", systemImage: "pencil")
                }
            }
        }
        .sheet(isPresented: $showingEditForm) {
            ProjectFormView(project: project, onSaved: onProjectChanged)
        }
        .sheet(isPresented: $showingNewSessionForm) {
            SessionFormView(project: project, session: nil, onSaved: { viewModel?.reload() })
        }
        .sheet(item: $sessionPendingEdit) { session in
            SessionFormView(project: project, session: session, onSaved: { viewModel?.reload() })
        }
        .alert(
            "Excluir sessão?",
            isPresented: Binding(get: { sessionPendingDeletion != nil }, set: { if !$0 { sessionPendingDeletion = nil } })
        ) {
            Button("Cancelar", role: .cancel) { sessionPendingDeletion = nil }
            Button("Excluir", role: .destructive) {
                if let session = sessionPendingDeletion {
                    viewModel?.deleteSession(session)
                }
                sessionPendingDeletion = nil
            }
        }
        .task {
            if viewModel == nil {
                viewModel = ProjectDetailViewModel(
                    project: project,
                    sessionRepository: dependencies.sessionRepository,
                    timerService: dependencies.timerService
                )
            }
        }
    }

    private func header(_ viewModel: ProjectDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: project.status.symbolName)
                Text(project.status.displayName)
                Text("•")
                Image(systemName: project.category.symbolName)
                Text(project.category.displayName)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Text(project.client)
                .font(.title3)

            if !project.descriptionText.isEmpty {
                Text(project.descriptionText)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            if !project.tags.isEmpty {
                HStack {
                    ForEach(project.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: Capsule())
                    }
                }
            }

            HStack(spacing: 12) {
                SummaryCardView(title: "Valor por dia", value: project.dailyRate.currencyFormatted, symbolName: "banknote")
                SummaryCardView(title: "Tempo acumulado", value: project.totalWorkedSeconds.formattedClock(showSeconds: false), symbolName: "clock")
                SummaryCardView(title: "Valor acumulado", value: project.totalValue.currencyFormatted, symbolName: "dollarsign.circle")
            }
            .padding(.top, 4)
        }
    }

    private func timerSection(_ viewModel: ProjectDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Timer").font(.headline)

            if viewModel.isRunning {
                Text(viewModel.elapsed.formattedClock(showSeconds: true))
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                HStack(spacing: 10) {
                    TimerControlButton(title: "Pausar", systemImage: "pause.fill") { viewModel.pause() }
                    TimerControlButton(title: "Encerrar", systemImage: "stop.fill", role: .destructive) { viewModel.stop() }
                }
            } else {
                HStack(spacing: 10) {
                    TimerControlButton(title: "Iniciar", systemImage: "play.fill") { viewModel.start() }
                    Button {
                        showingNewSessionForm = true
                    } label: {
                        Label("Adicionar sessão manualmente", systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func sessionsSection(_ viewModel: ProjectDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sessões").font(.headline)

            if viewModel.sessions.isEmpty {
                Text("Nenhuma sessão registrada ainda.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.sessions) { session in
                        HStack {
                            SessionRowView(session: session)
                            Spacer()
                            Menu {
                                Button("Editar") { sessionPendingEdit = session }
                                Button("Excluir", role: .destructive) { sessionPendingDeletion = session }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                            .menuStyle(.borderlessButton)
                            .frame(width: 24)
                        }
                        if session.id != viewModel.sessions.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}
