import SwiftUI
import AppKit

@MainActor
struct FolderSyncSettingsView: View {
    let service: FolderSyncService
    @State private var folderError: String?
    @State private var isPerformingAction = false

    private var isBusy: Bool { service.isSynchronizing || isPerformingAction }

    var body: some View {
        Form {
            Section {
                Text("Escolha a mesma pasta no iCloud Drive em cada Mac, com o iCloud Drive ativo na mesma conta Apple.")
                    .font(.callout)
                Button(service.folderPath == nil ? "Escolher pasta…" : "Alterar pasta…") {
                    chooseFolder()
                }
                .disabled(isBusy)

                if let path = service.folderPath {
                    Text(path)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Pasta de sincronização: \(path)")
                }
            } header: {
                Text("Pasta compartilhada")
            } footer: {
                Text("Alterar a pasta ou desativar preserva seus dados e os arquivos da pasta anterior.")
            }

            Section("Estado neste Mac") {
                HStack {
                    if isBusy {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Verificação em andamento")
                    }
                    Text(service.isEnabled ? service.status : "Sincronização desativada")
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let date = service.lastCheckDate {
                    LabeledContent("Última verificação local") {
                        Text(date, format: .dateTime.day().month().year().hour().minute())
                    }
                }

                if service.pendingUploadCount > 0 {
                    Text("Alterações aguardando envio à pasta: \(service.pendingUploadCount)")
                }
                if service.pendingDependencyCount > 0 {
                    Text("Registros aguardando versões relacionadas: \(service.pendingDependencyCount)")
                }

                HStack {
                    Button("Verificar agora") {
                        perform { await service.synchronize() }
                    }
                    .disabled(!service.isEnabled || isBusy)
                    Button("Desativar sincronização") {
                        service.disconnect()
                        folderError = nil
                    }
                    .disabled(!service.isEnabled || isBusy)
                }
            }

            if let error = folderError ?? service.errorMessage {
                Section("Não foi possível concluir") {
                    Text(error)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Confira o acesso à pasta, a conexão e o espaço no iCloud. Tente verificar novamente ou selecione a pasta outra vez.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !service.conflicts.isEmpty {
                Section {
                    Text("Este registro foi alterado em mais de um Mac. Escolha qual versão usar; as versões anteriores ficam no histórico.")
                        .font(.callout)
                    ForEach(service.conflicts) { conflict in
                        conflictRow(conflict)
                    }
                } header: {
                    Text("Conflitos (\(service.conflicts.count))")
                }
            }

            if !service.invoiceCollisions.isEmpty {
                Section {
                    Text("Faturas diferentes têm o mesmo número. Atribua um novo número a uma delas para manter cada fatura identificada.")
                        .font(.callout)
                    ForEach(service.invoiceCollisions) { collision in
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Número de fatura repetido: \(collision.number)", systemImage: "exclamationmark.triangle")
                                .font(.headline)
                            ForEach(collision.invoices) { invoice in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(invoice.client.isEmpty ? "Cliente não informado" : invoice.client)
                                    Text(invoice.id.uuidString)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                    Button("Atribuir novo número") {
                                        perform { await service.renumberInvoice(id: invoice.id) }
                                    }
                                    .accessibilityLabel("Atribuir novo número à fatura de \(invoice.client), identificador \(invoice.id.uuidString)")
                                    .disabled(!service.isEnabled || isBusy)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Numeração de faturas")
                }
            }

            Section {
                Text("O WorkLog verifica a pasta enquanto está aberto. O iCloud pode levar algum tempo para transportar os arquivos; uma verificação local não confirma que outro Mac recebeu as alterações.")
                Text("Sem conexão, você pode continuar trabalhando neste Mac. Sessões com o cronômetro em execução só entram na sincronização quando pausadas ou encerradas.")
            } header: {
                Text("Como funciona")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private func conflictRow(_ conflict: SyncConflict) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(conflict.key.entity.displayName)
                .font(.headline)
            Text("Identificador: \(conflict.key.id)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            HStack {
                Button("Manter versão deste Mac") {
                    perform { await service.keepLocal(conflict) }
                }
                Menu("Escolher versão…") {
                    ForEach(conflict.versions) { version in
                        Button(versionLabel(version)) {
                            perform { await service.resolve(conflict, using: version.payload) }
                        }
                    }
                }
            }
            .disabled(!service.isEnabled || isBusy)
        }
        .padding(.vertical, 4)
    }

    private func versionLabel(_ operation: SyncOperation) -> String {
        let action = operation.payload == nil ? "Exclusão" : "Registro"
        let date = operation.timestamp.formatted(date: .numeric, time: .standard)
        let device = String(operation.deviceID.uuidString.suffix(8))
        return "\(action) — \(date) — Mac \(device)"
    }

    private func perform(_ action: @escaping @MainActor () async -> Void) {
        guard !isBusy else { return }
        folderError = nil
        isPerformingAction = true
        Task { @MainActor in
            defer { isPerformingAction = false }
            await action()
        }
    }

    private func chooseFolder() {
        guard !isBusy else { return }
        let panel = NSOpenPanel()
        panel.title = "Escolher pasta de sincronização"
        panel.prompt = "Escolher pasta"
        panel.message = "Selecione a mesma pasta do iCloud Drive em todos os Macs."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        panel.level = .modalPanel
        panel.makeKeyAndOrderFront(nil)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try service.chooseFolder(url)
            folderError = nil
        } catch {
            folderError = error.localizedDescription
        }
    }
}
