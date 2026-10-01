import SwiftUI
import AppKit

struct MenuBarPopoverView: View {
    @Environment(\.dependencies) private var dependencies
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    @State private var menuBarViewModel: MenuBarViewModel?
    @State private var timerViewModel: TimerViewModel?
    @State private var projectListContentHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Divider()
            currentTimerSection
            Divider()
            listsSection
            Divider()
            footerSection
        }
        .padding(12)
        .frame(width: 320)
        .task { setupIfNeeded() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            AppLogoView(size: 20)
            Text("WorkLog")
                .font(.system(size: 13, weight: .semibold))
        }
    }

    @ViewBuilder
    private var currentTimerSection: some View {
        if let timerViewModel, let project = timerViewModel.activeProject {
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(project.name)
                Text(timerViewModel.elapsedFormatted)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
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
                .padding(.top, 4)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Nenhum timer ativo")
                    .font(.system(size: 13, weight: .medium))
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

    /// A lista ocupa só a altura do conteúdo, até o teto que mantém as ações visíveis.
    private static let projectListMaxHeight: CGFloat = 175

    @ViewBuilder
    private var listsSection: some View {
        if let menuBarViewModel {
            VStack(alignment: .leading, spacing: 8) {
                if !menuBarViewModel.favoriteProjects.isEmpty || !menuBarViewModel.recentProjects.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            if !menuBarViewModel.favoriteProjects.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    sectionHeader("Favoritos")
                                    ForEach(menuBarViewModel.favoriteProjects) { project in
                                        projectButton(project)
                                    }
                                }
                            }
                            if !menuBarViewModel.recentProjects.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    sectionHeader("Recentes")
                                    ForEach(menuBarViewModel.recentProjects) { project in
                                        projectButton(project)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: ProjectListHeightPreferenceKey.self,
                                    value: geometry.size.height
                                )
                            }
                        }
                    }
                    .frame(height: max(1, min(projectListContentHeight, Self.projectListMaxHeight)))
                    .onPreferenceChange(ProjectListHeightPreferenceKey.self) { height in
                        guard height.isFinite, height > 0,
                              abs(height - projectListContentHeight) > 0.5 else { return }
                        projectListContentHeight = height
                    }
                }

                HStack {
                    Text("Tempo total do dia")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(menuBarViewModel.todayTotal.formattedClock(showSeconds: false))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .font(.system(size: 12))
            }
        }
    }

    private func projectButton(_ project: Project) -> some View {
        Button { startTimer(for: project) } label: {
            ProjectRowView(project: project, isActive: project.id == timerViewModel?.activeProject?.id)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.vertical, 4)
                .padding(.horizontal, 4)
        }
        .buttonStyle(.borderless)
        .help(project.client.isEmpty ? project.name : "\(project.name) — \(project.client)")
    }

    private var footerSection: some View {
        VStack(spacing: 0) {
            footerButton("Abrir Dashboard", systemImage: "square.grid.2x2") {
                openWindow(id: "dashboard")
            }

            footerButton("Configurações", systemImage: "gearshape") {
                openSettings()
            }

            footerButton("Sair", systemImage: "power") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func footerButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 16)
                    .accessibilityHidden(true)
                Text(title)
            }
            .font(.system(size: 13))
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .accessibilityLabel(title)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
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

private struct ProjectListHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
