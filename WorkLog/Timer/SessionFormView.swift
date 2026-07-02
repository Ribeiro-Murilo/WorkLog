import SwiftUI

struct SessionFormView: View {
    @Environment(\.dependencies) private var dependencies
    @Environment(\.dismiss) private var dismiss

    let project: Project
    let session: Session?
    var onSaved: (() -> Void)?

    @State private var viewModel: SessionFormViewModel?

    var body: some View {
        NavigationStack {
            Form {
                if let viewModel {
                    Section("Período") {
                        DatePicker("Data", selection: Binding(get: { viewModel.date }, set: { viewModel.date = $0 }), displayedComponents: .date)
                        DatePicker("Início", selection: Binding(get: { viewModel.startTime }, set: { viewModel.startTime = $0 }))
                        DatePicker("Fim", selection: Binding(get: { viewModel.endTime }, set: { viewModel.endTime = $0 }))
                    }
                    Section("Observação") {
                        TextEditor(text: Binding(get: { viewModel.note }, set: { viewModel.note = $0 }))
                            .frame(minHeight: 80)
                    }
                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(session == nil ? "Nova Sessão" : "Editar Sessão")
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
            .frame(minWidth: 380, minHeight: 340)
            .task {
                if viewModel == nil {
                    viewModel = SessionFormViewModel(
                        project: project,
                        sessionRepository: dependencies.sessionRepository,
                        editing: session
                    )
                }
            }
        }
    }
}
