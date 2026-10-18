import AppKit
import SwiftUI

struct NotchPanelView: View {
    @Environment(\.dependencies) private var dependencies
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Bindable var viewModel: NotchPanelViewModel
    @Binding var isPinned: Bool
    var registersShortcuts = true
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            rule
            timerSection
            if let error = viewModel.errorMessage {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 1, green: 0.69, blue: 0.62))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Erro: \(error)")
            }
            rule
            searchField
            projectList
            rule
            HStack {
                Text("Registrado hoje").foregroundStyle(NotchPanelStyle.secondary)
                Spacer()
                Text(viewModel.todayTotal.formattedClock(showSeconds: false))
                    .fontWeight(.medium)
                    .monospacedDigit()
            }
            .font(.system(size: 12))
            rule
            footer
        }
        .padding(16)
        .frame(width: NotchPanelMetrics.contentWidth)
        .foregroundStyle(.white)
        .task {
            viewModel.reload()
            if registersShortcuts {
                QuickAccessShortcuts.register(dependencies: dependencies, toggleDashboard: toggleDashboardWindow)
            }
        }
        .onChange(of: dependencies.folderSyncService.dataRevision) { viewModel.reload() }
        .onChange(of: viewModel.isRunning) { viewModel.reload() }
    }

    private var header: some View {
        HStack {
            Text("WorkLog").font(.system(size: 14, weight: .semibold))
            Spacer()
            Button { isPinned.toggle() } label: {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 13))
                    .frame(width: 28, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(isPinned ? Color.white : NotchPanelStyle.secondary)
            .help(isPinned ? "Desafixar painel" : "Manter painel aberto")
            .accessibilityLabel(isPinned ? "Desafixar painel" : "Fixar painel aberto")
            .accessibilityValue(isPinned ? "Fixado" : "Desafixado")
        }
    }

    @ViewBuilder
    private var timerSection: some View {
        if let project = viewModel.project {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel(viewModel.state == .running ? "EM ANDAMENTO" : "PAUSADO")
                HStack(alignment: .top, spacing: 12) {
                    Circle().fill(NotchPanelStyle.projectColor(project.id))
                        .frame(width: 12, height: 12).padding(.top, 4)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(project.name)
                            .font(.system(size: 16, weight: .semibold))
                            .lineLimit(1).help(project.name)
                        if !project.client.isEmpty {
                            Text(project.client)
                                .font(.system(size: 12))
                                .foregroundStyle(NotchPanelStyle.secondary)
                                .lineLimit(1).help(project.client)
                        }
                    }
                }
                Text(viewModel.elapsedFormatted)
                    .font(.system(size: 42, weight: .regular, design: .monospaced))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 3)
                    .accessibilityLabel("Tempo da sessão: \(viewModel.elapsedFormatted)")
                if viewModel.state == .running {
                    HStack(spacing: 10) {
                        Button(action: viewModel.pause) { Label("Pausar", systemImage: "pause.fill") }
                            .buttonStyle(NotchPanelButtonStyle(prominent: true))
                        Button(action: viewModel.stop) { Label("Encerrar", systemImage: "stop.fill") }
                            .buttonStyle(NotchPanelButtonStyle())
                            .frame(width: 114)
                    }
                    .font(.system(size: 13, weight: .medium))
                } else {
                    Button(action: viewModel.resume) { Label("Retomar", systemImage: "play.fill") }
                        .font(.system(size: 13, weight: .medium))
                        .buttonStyle(NotchPanelButtonStyle(prominent: true))
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Pronto para começar")
                    .font(.system(size: 16, weight: .semibold))
                Text("Escolha um projeto para registrar seu tempo.")
                    .font(.system(size: 12))
                    .foregroundStyle(NotchPanelStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 5)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(NotchPanelStyle.secondary)
                .accessibilityHidden(true)
            TextField("", text: $viewModel.query, prompt:
                Text("Buscar projeto…").foregroundColor(NotchPanelStyle.secondary))
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onExitCommand {
                    if viewModel.query.isEmpty { searchFocused = false }
                    else { viewModel.query = "" }
                }
                .accessibilityLabel("Buscar projeto por nome ou cliente")
            if !viewModel.query.isEmpty {
                Button { viewModel.query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(NotchPanelStyle.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Limpar busca")
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 11)
        .frame(height: 34)
        .background(NotchPanelStyle.control, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(searchFocused ? Color.white.opacity(0.5) : Color.white.opacity(0.08))
        }
    }

    private var projectList: some View {
        let projects = viewModel.visibleProjects
        return VStack(alignment: .leading, spacing: 5) {
            sectionLabel(viewModel.query.isEmpty ? "TROCAR PROJETO" : "RESULTADOS")
            if projects.isEmpty {
                Text(viewModel.query.isEmpty ? "Seus projetos aparecerão aqui." : "Nenhum projeto encontrado.")
                    .font(.system(size: 12))
                    .foregroundStyle(NotchPanelStyle.secondary)
                    .padding(.vertical, 9)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(projects) { project in
                            NotchProjectButton(project: project) { viewModel.start(project: project) }
                            if project.id != projects.last?.id {
                                Rectangle().fill(NotchPanelStyle.divider)
                                    .frame(height: 1).padding(.leading, 30)
                            }
                        }
                    }
                }
                .frame(height: min(CGFloat(projects.count * 46 + max(0, projects.count - 1)), 144))
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button(action: toggleDashboardWindow) {
                Label("Abrir Dashboard", systemImage: "arrow.up.right")
                    .font(.system(size: 12))
                    .frame(minHeight: 26)
            }
            Spacer(minLength: 4)
            Button { openSettings() } label: {
                Image(systemName: "gearshape").frame(width: 26, height: 26)
            }
            .help("Configurações")
            .accessibilityLabel("Configurações")
            Menu {
                Button("Sair do WorkLog", systemImage: "power") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis").frame(width: 26, height: 26)
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Mais opções")
            .accessibilityLabel("Mais opções")
        }
        .buttonStyle(.plain)
        .foregroundStyle(NotchPanelStyle.secondary)
    }

    private var rule: some View { Rectangle().fill(NotchPanelStyle.divider).frame(height: 1) }

    private func sectionLabel(_ title: String) -> some View {
        Text(title).font(.system(size: 10, weight: .medium))
            .tracking(0.4).foregroundStyle(NotchPanelStyle.secondary)
    }

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

private struct NotchProjectButton: View {
    let project: Project
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Circle().fill(NotchPanelStyle.projectColor(project.id)).frame(width: 12, height: 12)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(project.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        if project.isFavorite {
                            Image(systemName: "star.fill").font(.system(size: 9))
                                .foregroundStyle(NotchPanelStyle.secondary)
                        }
                    }
                    if !project.client.isEmpty {
                        Text(project.client).font(.system(size: 11))
                            .foregroundStyle(NotchPanelStyle.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "play.fill").font(.system(size: 10))
                    .frame(width: 26, height: 26)
                    .overlay(Circle().strokeBorder(Color.white.opacity(hovering ? 0.6 : 0.3)))
            }
            .frame(height: 46)
            .padding(.horizontal, 6)
            .background(hovering ? Color.white.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(project.client.isEmpty ? project.name : "\(project.name) — \(project.client)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Iniciar \(project.name)\(project.client.isEmpty ? "" : ", \(project.client)")")
    }
}
