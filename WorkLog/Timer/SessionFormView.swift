import AppKit
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
                    SessionPeriodFields(viewModel: viewModel)
                    if !viewModel.conflictingSessions.isEmpty {
                        SessionConflictSection(
                            sessions: viewModel.conflictingSessions,
                            suggestedInterval: viewModel.suggestedInterval,
                            offersSuggestion: !viewModel.usesCycleEditor,
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
                    .disabled(viewModel == nil || viewModel?.isTimeEditingLocked == true)
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

/// Campos reais compartilhados com a verificação visual de dados sintéticos.
struct SessionPeriodFields: View {
    let viewModel: SessionFormViewModel

    var body: some View {
        if viewModel.isTimeEditingLocked {
            Section("Ciclos") {
                SessionCycleDetailsView(periods: viewModel.editingSession?.workPeriods ?? viewModel.cyclePeriods)
            }
        } else if viewModel.usesCycleEditor {
            ForEach(Array(viewModel.cyclePeriods.enumerated()), id: \.offset) { index, period in
                Section("Ciclo \(index + 1)") {
                    CycleDateField("Início", selection: Binding(
                        get: { viewModel.cyclePeriods[index].start },
                        set: { viewModel.updateCycleStart(at: index, to: $0) }
                    ))
                    if let end = period.end {
                        CycleDateField("Fim", selection: Binding(
                            get: { viewModel.cyclePeriods[index].end ?? end },
                            set: { viewModel.updateCycleEnd(at: index, to: $0) }
                        ))
                        LabeledContent("Duração") {
                            Text(max(0, end.timeIntervalSince(period.start)).formattedClock(showSeconds: true))
                                .monospacedDigit()
                        }
                    } else {
                        LabeledContent("Fim", value: "Em andamento")
                    }
                }
            }
            Section {
                LabeledContent("Tempo trabalhado") {
                    Text(viewModel.cyclesTotal.formattedClock(showSeconds: true)).monospacedDigit()
                }
                Text("As pausas entre os ciclos não entram no total.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } else {
            Section("Período") {
                DatePicker("Data", selection: Binding(get: { viewModel.date }, set: { viewModel.date = $0 }), displayedComponents: .date)
                DatePicker("Início", selection: Binding(get: { viewModel.startTime }, set: { viewModel.startTime = $0 }))
                DatePicker("Fim", selection: Binding(get: { viewModel.endTime }, set: { viewModel.endTime = $0 }))
            }
        }
        if let explanation = viewModel.timeEditingExplanation {
            Text(explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let message = viewModel.cycleValidationMessage {
            Text(message)
                .font(.callout)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Horários inválidos: \(message)")
        }
    }
}

/// O DatePicker SwiftUI no macOS não oferece segundos. O controle AppKit mantém
/// datas completas e precisão de segundos, inclusive em ciclos curtos.
private struct CycleDateField: View {
    let title: String
    @Binding var selection: Date

    init(_ title: String, selection: Binding<Date>) {
        self.title = title
        _selection = selection
    }

    var body: some View {
        LabeledContent(title) {
            CycleDatePicker(title: title, selection: $selection)
                .frame(width: 270, height: 24)
        }
    }
}

private struct CycleDatePicker: NSViewRepresentable {
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    @Environment(\.timeZone) private var timeZone
    let title: String
    @Binding var selection: Date

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = [.yearMonthDay, .hourMinuteSecond]
        picker.datePickerMode = .single
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.changed(_:))
        return picker
    }

    func updateNSView(_ picker: NSDatePicker, context: Context) {
        context.coordinator.selection = $selection
        picker.locale = locale
        picker.calendar = calendar
        picker.timeZone = timeZone
        picker.dateValue = selection
        picker.setAccessibilityLabel(title)
    }

    final class Coordinator: NSObject {
        var selection: Binding<Date>
        init(selection: Binding<Date>) { self.selection = selection }
        @objc func changed(_ picker: NSDatePicker) { selection.wrappedValue = picker.dateValue }
    }
}


/// Native form section shared by creation and editing, with explicit suggestion application.
struct SessionConflictSection: View {
    @Environment(\.locale) private var locale

    let sessions: [Session]
    let suggestedInterval: DateInterval?
    var offersSuggestion = true
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
                    ForEach(Array(session.occupiedWorkIntervals.enumerated()), id: \.offset) { _, interval in
                        Text(intervalLabel(start: interval.start, end: interval.end == .distantFuture ? nil : interval.end))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
            } else if offersSuggestion {
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
