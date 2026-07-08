import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsRootView: View {
    @Environment(\.dependencies) private var dependencies
    @State private var viewModel: SettingsViewModel?
    @State private var backupErrorMessage: String?

    private let idleTimeoutOptions = [5, 10, 15, 30, 60]

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("Geral", systemImage: "gearshape") }

            shortcutsTab
                .tabItem { Label("Atalhos", systemImage: "keyboard") }

            billingTab
                .tabItem { Label("Faturamento", systemImage: "doc.text") }

            backupTab
                .tabItem { Label("Backup", systemImage: "externaldrive") }

            updatesTab
                .tabItem { Label("Atualizações", systemImage: "arrow.down.circle") }

            aboutTab
                .tabItem { Label("Sobre", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 360)
        .alert(
            "Erro",
            isPresented: Binding(get: { backupErrorMessage != nil }, set: { if !$0 { backupErrorMessage = nil } })
        ) {
            Button("OK", role: .cancel) { backupErrorMessage = nil }
        } message: {
            Text(backupErrorMessage ?? "")
        }
        .task { setupIfNeeded() }
    }

    @ViewBuilder
    private var generalTab: some View {
        if let viewModel {
            Form {
                Toggle("Inicializar junto com o macOS", isOn: Binding(
                    get: { viewModel.launchAtLogin },
                    set: { viewModel.launchAtLogin = $0; viewModel.save() }
                ))

                Picker("Onde exibir o WorkLog", selection: Binding(
                    get: { viewModel.displayMode },
                    set: { viewModel.displayMode = $0; viewModel.save(); dependencies.displayModeManager.refresh() }
                )) {
                    ForEach(AppDisplayMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Text("Se a tela atual não tiver notch, o WorkLog usa a barra de menu automaticamente.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Pausa automática por inatividade", selection: Binding(
                    get: { viewModel.idleTimeoutMinutes },
                    set: { viewModel.idleTimeoutMinutes = $0; viewModel.save() }
                )) {
                    ForEach(idleTimeoutOptions, id: \.self) { minutes in
                        Text("\(minutes) minutos").tag(minutes)
                    }
                }

                Toggle("Mostrar segundos", isOn: Binding(
                    get: { viewModel.showSeconds },
                    set: { viewModel.showSeconds = $0; viewModel.save() }
                ))

                Picker("Tema", selection: Binding(
                    get: { viewModel.theme },
                    set: { viewModel.theme = $0; viewModel.save() }
                )) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }

                Picker("Formato de hora", selection: Binding(
                    get: { viewModel.timeFormat },
                    set: { viewModel.timeFormat = $0; viewModel.save() }
                )) {
                    ForEach(TimeFormatPreference.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }

                Toggle("Incluir logo do app nos PDFs", isOn: Binding(
                    get: { viewModel.includeLogoInPDF },
                    set: { viewModel.includeLogoInPDF = $0; viewModel.save() }
                ))
            }
            .formStyle(.grouped)
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private var shortcutsTab: some View {
        if let viewModel {
            Form {
                ForEach(viewModel.shortcutBindings) { binding in
                    LabeledContent(binding.action.displayName) {
                        ShortcutRecorderView(keyCombo: Binding(
                            get: { binding.keyCombo },
                            set: { viewModel.updateShortcut(action: binding.action, keyCombo: $0) }
                        ))
                    }
                }
            }
            .formStyle(.grouped)
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private var billingTab: some View {
        if let viewModel {
            Form {
                Section {
                    TextField("Nome do emissor", text: Binding(
                        get: { viewModel.invoiceIssuerName },
                        set: { viewModel.invoiceIssuerName = $0; viewModel.save() }
                    ))
                    TextEditor(text: Binding(
                        get: { viewModel.invoiceIssuerDetails },
                        set: { viewModel.invoiceIssuerDetails = $0; viewModel.save() }
                    ))
                    .frame(height: 80)
                    .font(.callout)
                } header: {
                    Text("Emissor da nota")
                } footer: {
                    Text("Aparecem no cabeçalho das notas de faturamento. Ex.: CPF/CNPJ, PIX, endereço.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        } else {
            ProgressView()
        }
    }

    private var backupTab: some View {
        Form {
            Section("Backup") {
                Button("Exportar backup…") { exportBackup() }
                Button("Importar backup…") { importBackup() }
            }
            Section("Exportação de relatórios") {
                Text("Utilize a tela de Relatórios para exportar sessões em CSV, Excel ou PDF.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var aboutTab: some View {
        VStack(spacing: 12) {
            Spacer()
            AppLogoView(size: 96, cornerRadius: 20)
            Text("WorkLog")
                .font(.title.bold())
            Text("Versão \(appVersion) (\(appBuild))")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Controle pessoal de tempo em projetos e demandas.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var updatesTab: some View {
        Form {
            Section {
                LabeledContent("Versão instalada", value: "\(appVersion) (\(appBuild))")
                Button("Verificar atualizações…") {
                    dependencies.updateService.checkForUpdates()
                }
                .disabled(!dependencies.updateService.canCheckForUpdates)
            } footer: {
                Text("A checagem é sempre manual — o WorkLog nunca busca atualizações sozinho em segundo plano. Se houver uma nova versão, você decide se instala.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private func exportBackup() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "WorkLog-Backup.json"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.json]
        guard runPanel(panel) == .OK, let url = panel.url else { return }
        do {
            try dependencies.backupService.exportBackup(to: url)
        } catch {
            backupErrorMessage = error.localizedDescription
        }
    }

    private func importBackup() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        guard runPanel(panel) == .OK, let url = panel.url else { return }
        do {
            try dependencies.backupService.importBackup(from: url)
        } catch {
            backupErrorMessage = error.localizedDescription
        }
    }

    /// Exibe um `NSSavePanel`/`NSOpenPanel` a partir de um app acessório
    /// (`LSUIElement`). Sem ativar a app e elevar o nível do painel, ele abre
    /// atrás das outras janelas ou sem foco, impedindo exportar/importar.
    private func runPanel(_ panel: NSSavePanel) -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        panel.level = .modalPanel
        panel.makeKeyAndOrderFront(nil)
        return panel.runModal()
    }

    private func setupIfNeeded() {
        if viewModel == nil {
            viewModel = SettingsViewModel(
                settingsRepository: dependencies.settingsRepository,
                launchAtLoginService: dependencies.launchAtLoginService,
                idleDetectionService: dependencies.idleDetectionService,
                shortcutBindingRepository: dependencies.shortcutBindingRepository,
                shortcutsService: dependencies.shortcutsService
            )
        }
    }
}
