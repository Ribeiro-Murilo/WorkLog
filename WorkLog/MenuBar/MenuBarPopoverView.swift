import SwiftUI
import AppKit

struct MenuBarPopoverView: View {
    @Environment(\.dependencies) private var dependencies
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    @State private var menuBarViewModel: MenuBarViewModel?
    @State private var timerViewModel: TimerViewModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            currentTimerSection
            Divider()
            listsSection
            Divider()
            footerSection
        }
        .padding(16)
        .frame(width: 320)
        .task { setupIfNeeded() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            AppLogoView(size: 22)
            Text("WorkLog")
                .font(.headline)
        }
    }

    @ViewBuilder
    private var currentTimerSection: some View {
        if let timerViewModel, let project = timerViewModel.activeProject {
            VStack(alignment: .leading, spacing: 6) {
                Text(project.name)
                    .font(.headline)
                Text(timerViewModel.elapsedFormatted)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()

                HStack(spacing: 8) {
                    TimerControlButton(title: "Pausar", systemImage: "pause.fill") {
                        timerViewModel.pause()
                        menuBarViewModel?.reload()
                    }
                    TimerControlButton(title: "Encerrar", systemImage: "stop.fill", role: .destructive) {
                        timerViewModel.stop()
                        menuBarViewModel?.reload()
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Nenhum timer ativo")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                if let timerViewModel {
                    TimerControlButton(title: "Continuar", systemImage: "play.fill") {
                        timerViewModel.resume()
                        menuBarViewModel?.reload()
                    }
                }
            }
        }
    }

    /// Altura máxima da lista rolável de projetos: cabem ~5 linhas antes de rolar, para
    /// que favoritos + recentes nunca empurrem o rodapé (dashboard/config/sair) para
    /// fora da área visível do notch, que tem altura fixa.
    private static let projectListMaxHeight: CGFloat = 175

    @ViewBuilder
    private var listsSection: some View {
        if let menuBarViewModel {
            if !menuBarViewModel.favoriteProjects.isEmpty || !menuBarViewModel.recentProjects.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if !menuBarViewModel.favoriteProjects.isEmpty {
                            sectionHeader("Favoritos")
                            ForEach(menuBarViewModel.favoriteProjects) { project in
                                Button { startTimer(for: project) } label: {
                                    ProjectRowView(project: project, isActive: project.id == timerViewModel?.activeProject?.id)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        if !menuBarViewModel.recentProjects.isEmpty {
                            sectionHeader("Recentes")
                            ForEach(menuBarViewModel.recentProjects) { project in
                                Button { startTimer(for: project) } label: {
                                    ProjectRowView(project: project, isActive: project.id == timerViewModel?.activeProject?.id)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .frame(maxHeight: Self.projectListMaxHeight)
            }

            HStack {
                Text("Tempo total do dia")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(menuBarViewModel.todayTotal.formattedClock(showSeconds: false))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var footerSection: some View {
        VStack(spacing: 4) {
            Button {
                openWindow(id: "dashboard")
            } label: {
                Label("Abrir Dashboard", systemImage: "square.grid.2x2")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                openSettings()
            } label: {
                Label("Configurações", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Sair", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 2)
    }

    private func startTimer(for project: Project) {
        timerViewModel?.start(project: project)
        menuBarViewModel?.reload()
    }

    private func setupIfNeeded() {
        if menuBarViewModel == nil {
            menuBarViewModel = MenuBarViewModel(
                timerService: dependencies.timerService,
                projectRepository: dependencies.projectRepository,
                sessionRepository: dependencies.sessionRepository,
                settingsRepository: dependencies.settingsRepository
            )
        }
        if timerViewModel == nil {
            timerViewModel = TimerViewModel(
                timerService: dependencies.timerService,
                settingsRepository: dependencies.settingsRepository
            )
        }
        registerGlobalShortcuts()
    }

    private func registerGlobalShortcuts() {
        try? dependencies.shortcutsService.registerDefaultsIfNeeded()

        try? dependencies.shortcutsService.register(action: .startTimer) {
            Task { @MainActor in
                timerViewModel?.resume()
                menuBarViewModel?.reload()
            }
        }
        try? dependencies.shortcutsService.register(action: .pauseTimer) {
            Task { @MainActor in
                timerViewModel?.pause()
                menuBarViewModel?.reload()
            }
        }
        try? dependencies.shortcutsService.register(action: .openDashboard) {
            Task { @MainActor in toggleDashboardWindow() }
        }
        try? dependencies.shortcutsService.register(action: .openPopover) {
            Task { @MainActor in toggleDashboardWindow() }
        }
        try? dependencies.shortcutsService.register(action: .newProject) {
            Task { @MainActor in toggleDashboardWindow() }
        }
        try? dependencies.shortcutsService.register(action: .searchProject) {
            Task { @MainActor in toggleDashboardWindow() }
        }
    }

    /// Mostra e foca a janela do dashboard; se ela já estiver em primeiro plano, esconde.
    /// A cena é singleton (`Window`, não `WindowGroup`), então `openWindow` nunca duplica —
    /// aqui só cuidamos de trazer para frente / ativar o app, que o SwiftUI não faz sozinho.
    @MainActor
    private func toggleDashboardWindow() {
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("dashboard") == true }) {
            if window.isVisible && NSApp.isActive {
                window.orderOut(nil)
            } else {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            }
        } else {
            openWindow(id: "dashboard")
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
