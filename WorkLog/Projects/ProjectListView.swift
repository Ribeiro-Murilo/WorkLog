import SwiftUI

struct ProjectListView: View {
    @Environment(\.dependencies) private var dependencies
    @State private var viewModel: ProjectListViewModel?
    @State private var showingNewProjectForm = false
    @State private var projectPendingDeletion: Project?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Projetos")
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        filterMenu
                        sortMenu
                        Button {
                            showingNewProjectForm = true
                        } label: {
                            Label("Novo Projeto", systemImage: "plus")
                        }
                    }
                }
                .sheet(isPresented: $showingNewProjectForm) {
                    ProjectFormView(project: nil)
                }
                .alert(
                    "Excluir projeto?",
                    isPresented: Binding(
                        get: { projectPendingDeletion != nil },
                        set: { if !$0 { projectPendingDeletion = nil } }
                    )
                ) {
                    Button("Cancelar", role: .cancel) { projectPendingDeletion = nil }
                    Button("Excluir", role: .destructive) {
                        if let project = projectPendingDeletion {
                            viewModel?.delete(project)
                        }
                        projectPendingDeletion = nil
                    }
                } message: {
                    Text("Essa ação também removerá todas as sessões associadas a este projeto.")
                }
        }
        .task { setupIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        if let viewModel {
            List(viewModel.projects) { project in
                NavigationLink(value: project) {
                    ProjectRowView(project: project)
                }
                .contextMenu {
                    Button {
                        viewModel.toggleFavorite(project)
                    } label: {
                        Label(project.isFavorite ? "Remover dos favoritos" : "Marcar como favorito", systemImage: "star")
                    }
                    Button {
                        viewModel.toggleArchive(project)
                    } label: {
                        Label(project.isArchived ? "Desarquivar" : "Arquivar", systemImage: "archivebox")
                    }
                    Divider()
                    Button(role: .destructive) {
                        projectPendingDeletion = project
                    } label: {
                        Label("Excluir", systemImage: "trash")
                    }
                }
            }
            .searchable(text: Binding(get: { viewModel.searchQuery }, set: { viewModel.searchQuery = $0 }), prompt: "Pesquisar projetos")
            .navigationDestination(for: Project.self) { project in
                ProjectDetailView(project: project, onProjectChanged: viewModel.reload)
            }
            .overlay {
                if viewModel.projects.isEmpty {
                    ContentUnavailableView(
                        "Nenhum projeto encontrado",
                        systemImage: "folder",
                        description: Text("Crie um novo projeto para começar a controlar o tempo.")
                    )
                }
            }
        } else {
            ProgressView()
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Status", selection: statusBinding) {
                Text("Todos os status").tag(ProjectStatus?.none)
                ForEach(ProjectStatus.allCases) { status in
                    Text(status.displayName).tag(ProjectStatus?.some(status))
                }
            }
            Picker("Categoria", selection: categoryBinding) {
                Text("Todas as categorias").tag(ProjectCategory?.none)
                ForEach(ProjectCategory.allCases) { category in
                    Text(category.displayName).tag(ProjectCategory?.some(category))
                }
            }
            Toggle("Incluir arquivados", isOn: includeArchivedBinding)
        } label: {
            Label("Filtrar", systemImage: "line.3.horizontal.decrease.circle")
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Ordenar por", selection: sortBinding) {
                ForEach(ProjectSortOption.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
        } label: {
            Label("Ordenar", systemImage: "arrow.up.arrow.down")
        }
    }

    private var statusBinding: Binding<ProjectStatus?> {
        Binding(get: { viewModel?.statusFilter }, set: { viewModel?.statusFilter = $0 })
    }

    private var categoryBinding: Binding<ProjectCategory?> {
        Binding(get: { viewModel?.categoryFilter }, set: { viewModel?.categoryFilter = $0 })
    }

    private var includeArchivedBinding: Binding<Bool> {
        Binding(get: { viewModel?.includeArchived ?? false }, set: { viewModel?.includeArchived = $0 })
    }

    private var sortBinding: Binding<ProjectSortOption> {
        Binding(get: { viewModel?.sortOption ?? .name }, set: { viewModel?.sortOption = $0 })
    }

    private func setupIfNeeded() {
        if viewModel == nil {
            viewModel = ProjectListViewModel(repository: dependencies.projectRepository)
        }
    }
}
