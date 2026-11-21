import SwiftUI

struct ProjectDetailView: View {
    @Environment(\.dependencies) private var dependencies
    @Environment(PTAXService.self) private var ptax
    let project: Project
    var onProjectChanged: (() -> Void)?

    @State private var viewModel: ProjectDetailViewModel?
    @State private var showingEditForm = false
    @State private var showingNewSessionForm = false
    @State private var sessionPendingEdit: Session?
    @State private var sessionPendingDeletion: Session?
    @State private var newCommentText: String = ""
    @State private var commentPendingDeletion: Comment?
    @AppStorage private var displayCurrencyCode: String

    init(project: Project, onProjectChanged: (() -> Void)? = nil) {
        self.project = project
        self.onProjectChanged = onProjectChanged
        _displayCurrencyCode = AppStorage(wrappedValue: "", "project-display-currency.\(project.id.uuidString)")
    }

    var body: some View {
        ScrollView {
            if let viewModel {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    Divider()
                    timerSection(viewModel)
                    Divider()
                    commentsSection(viewModel)
                    Divider()
                    sessionsSection(viewModel)
                }
                .padding(20)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(project.name)
        .onChange(of: dependencies.folderSyncService.dataRevision) { viewModel?.reload() }
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
        .alert(
            "Excluir comentário?",
            isPresented: Binding(get: { commentPendingDeletion != nil }, set: { if !$0 { commentPendingDeletion = nil } })
        ) {
            Button("Cancelar", role: .cancel) { commentPendingDeletion = nil }
            Button("Excluir", role: .destructive) {
                if let comment = commentPendingDeletion {
                    viewModel?.deleteComment(comment)
                }
                commentPendingDeletion = nil
            }
        }
        .task {
            if viewModel == nil {
                viewModel = ProjectDetailViewModel(
                    project: project,
                    sessionRepository: dependencies.sessionRepository,
                    commentRepository: dependencies.commentRepository,
                    timerService: dependencies.timerService
                )
            }
        }
    }

    private var header: some View {
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

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) { summaryCards(fillsRowHeight: true) }
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 8) { summaryCards(fillsRowHeight: false) }
            }
            .padding(.top, 4)

            Text(exchangeRateStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var displayCurrency: Binding<ProjectCurrency> {
        Binding {
            ProjectCurrency(rawValue: displayCurrencyCode) ?? project.currency
        } set: { currency in
            displayCurrencyCode = currency.rawValue
        }
    }

    @ViewBuilder
    private func summaryCards(fillsRowHeight: Bool) -> some View {
        ProjectMoneyCard(
            title: "Valor por dia", symbolName: "banknote", amount: project.dailyRate,
            currency: project.currency, displayCurrency: displayCurrency.wrappedValue,
            fillsRowHeight: fillsRowHeight
        )
        .frame(minWidth: 138)
        SummaryCardView(
            title: "Tempo acumulado",
            value: project.totalWorkedSeconds.formattedClock(showSeconds: false),
            symbolName: "clock",
            fillsRowHeight: fillsRowHeight
        )
        .frame(minWidth: 126)
        ProjectMoneyCard(
            title: "Valor acumulado", symbolName: "dollarsign.circle", amount: project.totalValue,
            currency: project.currency, displayCurrency: displayCurrency.wrappedValue,
            selection: displayCurrency, fillsRowHeight: fillsRowHeight
        )
        .frame(minWidth: 185)
    }

    private var exchangeRateStatus: String {
        if let date = ptax.snapshot?.bulletinDate {
            let displayDate = date.split(separator: "-").reversed().joined(separator: "/")
            let source = ptax.isUsingCachedRates ? "PTAX de venda em cache" : "PTAX de venda"
            return "\(source) · \(displayDate) · Moeda do projeto: \(project.currency.rawValue)"
        }
        let status = ptax.isRefreshing ? "Buscando cotação PTAX…" : "Cotação PTAX indisponível"
        return "\(status) · Moeda do projeto: \(project.currency.rawValue)"
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
                    if viewModel.canResume {
                        TimerControlButton(title: "Retomar", systemImage: "play.fill") { viewModel.resume() }
                    } else {
                        TimerControlButton(title: "Iniciar", systemImage: "play.fill") { viewModel.start() }
                            .disabled(project.isArchived)
                    }
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
                        HStack(alignment: .top) {
                            SessionRowView(session: session, onEditCycles: { sessionPendingEdit = session })
                            Menu {
                                Button("Editar") { sessionPendingEdit = session }
                                Button("Excluir", role: .destructive) { sessionPendingDeletion = session }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                            .menuStyle(.borderlessButton)
                            .frame(width: 24)
                            .padding(.top, 4)
                        }
                        if session.id != viewModel.sessions.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func commentsSection(_ viewModel: ProjectDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Comentários").font(.headline)

            HStack(alignment: .top, spacing: 8) {
                TextField("Adicionar um comentário…", text: $newCommentText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .onSubmit { addComment(viewModel) }
                Button {
                    addComment(viewModel)
                } label: {
                    Label("Adicionar", systemImage: "plus.circle")
                }
                .buttonStyle(.bordered)
                .disabled(newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if viewModel.comments.isEmpty {
                Text("Nenhum comentário ainda.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.comments) { comment in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(comment.author)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                    Text("•")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(comment.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(comment.text)
                                    .font(.body)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                commentPendingDeletion = comment
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .frame(width: 24)
                        }
                        .padding(.vertical, 6)
                        if comment.id != viewModel.comments.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func addComment(_ viewModel: ProjectDetailViewModel) {
        viewModel.addComment(text: newCommentText)
        newCommentText = ""
    }
}
