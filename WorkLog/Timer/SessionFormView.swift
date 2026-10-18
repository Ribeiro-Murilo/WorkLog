import SwiftUI

struct SessionFormView: View {
    @Environment(\.dependencies) private var dependencies
    @Environment(\.dismiss) private var dismiss

    let project: Project
    let session: Session?
    var onSaved: (() -> Void)?

    @State private var viewModel: SessionFormViewModel?
    @State private var viewModelProjectID: UUID?

    var body: some View {
        NavigationStack {
            Form {
                if let viewModel {
                    Section("Período") {
                        DatePicker("Data", selection: Binding(get: { viewModel.date }, set: { viewModel.date = $0 }), displayedComponents: .date)
                        DatePicker("Início", selection: Binding(get: { viewModel.startTime }, set: { viewModel.startTime = $0 }))
                        DatePicker("Fim", selection: Binding(get: { viewModel.endTime }, set: { viewModel.endTime = $0 }))
                    }
                    if !viewModel.conflictingSessions.isEmpty {
                        SessionConflictSection(
                            sessions: viewModel.conflictingSessions,
                            suggestedInterval: viewModel.suggestedInterval,
                            onApply: viewModel.applySuggestedInterval
                        )
                    }
                    if let availabilityError = viewModel.availabilityError {
                        Text(availabilityError)
                            .foregroundStyle(.red)
                            .font(.callout)
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
            .frame(minWidth: 420, idealWidth: 480, minHeight: 440, idealHeight: 580)
            .task(id: project.id) {
                if viewModel == nil || viewModelProjectID != project.id {
                    viewModelProjectID = project.id
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


/// Native form section shared by creation and editing, with explicit suggestion application.
struct SessionConflictSection: View {
    @Environment(\.locale) private var locale

    let sessions: [Session]
    let suggestedInterval: DateInterval?
    let onApply: () -> Void

    var body: some View {
        Section("Conflitos de horário") {
            Text("O período coincide com as sessões abaixo. Escolha outro horário antes de salvar.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(sessions) { session in
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.project?.name ?? "Projeto removido")
                        .fontWeight(.medium)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(intervalLabel(start: session.startTime, end: session.endTime))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 2)
            }
            if let suggestedInterval {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Horário disponível mais próximo")
                        .font(.callout)
                        .fontWeight(.medium)
                    Text(intervalLabel(start: suggestedInterval.start, end: suggestedInterval.end))
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Usar horário sugerido", action: onApply)
                }
                .padding(.vertical, 4)
            } else {
                Text("Não há horário livre com essa duração no mesmo dia do início. Altere a data ou a duração.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func intervalLabel(start: Date, end: Date?) -> String {
        let format = Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale)
        let startLabel = start.formatted(format)
        guard let end else { return "\(startLabel) até encerrar o timer (em execução)" }
        let endLabel = end.formatted(format)
        return "\(startLabel) – \(endLabel)"
    }
}
