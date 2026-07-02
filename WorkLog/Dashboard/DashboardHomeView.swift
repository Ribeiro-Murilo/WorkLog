import SwiftUI

struct DashboardHomeView: View {
    @Environment(\.dependencies) private var dependencies
    @State private var viewModel: DashboardViewModel?

    var body: some View {
        ScrollView {
            if let viewModel {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 10) {
                        AppLogoView(size: 32, cornerRadius: 8)
                        Text("Resumo")
                            .font(.largeTitle.bold())
                    }
                    summaryGrid(viewModel)
                    HStack(alignment: .top, spacing: 20) {
                        recentSessionsSection(viewModel)
                        mostUsedProjectsSection(viewModel)
                    }
                    HStack(alignment: .top, spacing: 20) {
                        breakdownSection(title: "Tempo por categoria", items: viewModel.timeByCategory.map { ($0.category.displayName, $0.total) })
                        breakdownSection(title: "Tempo por cliente", items: viewModel.timeByClient)
                    }
                    breakdownSection(title: "Tempo por projeto", items: viewModel.timeByProject.map { ($0.project.name, $0.total) })
                }
                .padding(20)
            } else {
                ProgressView()
                    .padding(40)
            }
        }
        .navigationTitle("Resumo")
        .task {
            if viewModel == nil {
                viewModel = DashboardViewModel(
                    projectRepository: dependencies.projectRepository,
                    sessionRepository: dependencies.sessionRepository
                )
            }
        }
    }

    private func summaryGrid(_ viewModel: DashboardViewModel) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
            SummaryCardView(title: "Hoje", value: viewModel.todayTotal.formattedClock(showSeconds: false), symbolName: "sun.max")
            SummaryCardView(title: "Semana", value: viewModel.weekTotal.formattedClock(showSeconds: false), symbolName: "calendar")
            SummaryCardView(title: "Mês", value: viewModel.monthTotal.formattedClock(showSeconds: false), symbolName: "calendar.badge.clock")
            SummaryCardView(title: "Tempo total", value: viewModel.allTimeTotal.formattedClock(showSeconds: false), symbolName: "clock")
            SummaryCardView(title: "Projetos ativos", value: "\(viewModel.activeProjectsCount)", symbolName: "folder")
            SummaryCardView(title: "Projetos arquivados", value: "\(viewModel.archivedProjectsCount)", symbolName: "archivebox")
        }
    }

    private func recentSessionsSection(_ viewModel: DashboardViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Últimas sessões").font(.headline)
            if viewModel.recentSessions.isEmpty {
                Text("Nenhuma sessão registrada.").font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.recentSessions) { session in
                        SessionRowView(session: session)
                        if session.id != viewModel.recentSessions.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
    }

    private func mostUsedProjectsSection(_ viewModel: DashboardViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Projetos mais utilizados").font(.headline)
            if viewModel.mostUsedProjects.isEmpty {
                Text("Sem dados ainda.").font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(viewModel.mostUsedProjects.prefix(6), id: \.project.id) { entry in
                        HStack {
                            Text(entry.project.name).font(.system(size: 13))
                            Spacer()
                            Text(entry.total.formattedClock(showSeconds: false))
                                .font(.system(size: 13))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
    }

    private func breakdownSection(title: String, items: [(String, TimeInterval)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            if items.isEmpty {
                Text("Sem dados ainda.").font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(items.prefix(8).enumerated()), id: \.offset) { _, item in
                        HStack {
                            Text(item.0).font(.system(size: 13))
                            Spacer()
                            Text(item.1.formattedClock(showSeconds: false))
                                .font(.system(size: 13))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
    }
}
