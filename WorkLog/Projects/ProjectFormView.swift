import SwiftUI

struct ProjectFormView: View {
    @Environment(\.dependencies) private var dependencies
    @Environment(\.dismiss) private var dismiss

    let project: Project?
    var onSaved: (() -> Void)?

    @State private var viewModel: ProjectFormViewModel?

    var body: some View {
        NavigationStack {
            Form {
                if let viewModel {
                    Section("Informações básicas") {
                        TextField("Nome do projeto", text: Binding(get: { viewModel.name }, set: { viewModel.name = $0 }))
                        TextField("Cliente", text: Binding(get: { viewModel.client }, set: { viewModel.client = $0 }))
                        TextField("Valor por dia (R$)", text: Binding(get: { viewModel.dailyRateText }, set: { viewModel.dailyRateText = $0 }))
                    }

                    Section("Classificação") {
                        Picker("Categoria", selection: Binding(get: { viewModel.category }, set: { viewModel.category = $0 })) {
                            ForEach(ProjectCategory.allCases) { category in
                                Text(category.displayName).tag(category)
                            }
                        }
                        Picker("Status", selection: Binding(get: { viewModel.status }, set: { viewModel.status = $0 })) {
                            ForEach(ProjectStatus.allCases) { status in
                                Text(status.displayName).tag(status)
                            }
                        }
                        TextField("Tags (separadas por vírgula)", text: Binding(get: { viewModel.tagsText }, set: { viewModel.tagsText = $0 }))
                    }

                    Section("Descrição") {
                        TextEditor(text: Binding(get: { viewModel.descriptionText }, set: { viewModel.descriptionText = $0 }))
                            .frame(minHeight: 100)
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(project == nil ? "Novo Projeto" : "Editar Projeto")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        if viewModel?.save() == true {
                            onSaved?()
                            dismiss()
                        }
                    }
                }
            }
            .frame(minWidth: 420, minHeight: 420)
            .task {
                if viewModel == nil {
                    viewModel = ProjectFormViewModel(repository: dependencies.projectRepository, editing: project)
                }
            }
        }
    }
}
