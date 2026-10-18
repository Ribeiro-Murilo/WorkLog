import AppKit
import SwiftUI
import Testing
@testable import WorkLog

/// Capturas opcionais, fora da tela e com dados sintéticos; nunca abre WorkLog.app.
@MainActor
struct NotchPanelRenderingTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["WORKLOG_NOTCH_PREVIEW_DIR"] != nil))
    func renderApprovedPanelStates() throws {
        guard let output = ProcessInfo.processInfo.environment["WORKLOG_NOTCH_PREVIEW_DIR"] else { return }
        try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
        // Reusa o container de testes: múltiplos schemas concorrentes dos mesmos
        // modelos causam um trap do SwiftData nesta toolchain.
        let dependencies = DependencyContainer(modelContext: makeInMemoryContext())
        _ = NSApplication.shared
        let timer = NotchPreviewTimer()
        let project = Project(name: "WorkLog", client: "Projeto pessoal", dailyRate: 0, category: .personal)
        try dependencies.projectRepository.insert(project)
        for (name, client) in [("BibleAI", "Projeto pessoal"), ("Tutus Gestão", "Produto"), ("WhatsDot", "Integrações")] {
            let item = Project(name: name, client: client, dailyRate: 0, category: .work, isFavorite: true)
            try dependencies.projectRepository.insert(item)
        }
        let start = Date.now.addingTimeInterval(-3600)
        try dependencies.sessionRepository.insert(Session(project: project, date: start, startTime: start,
            endTime: .now, durationSeconds: 16320, category: .personal, status: .completed))
        let model = NotchPanelViewModel(timerService: timer, projectRepository: dependencies.projectRepository,
            sessionRepository: dependencies.sessionRepository, settingsRepository: dependencies.settingsRepository)

        timer.activeProject = project
        timer.activeSession = Session(project: project, date: .now, startTime: .now, category: .personal)
        timer.elapsed = 5076
        try capture("notch-running", model: model, dependencies: dependencies, output: output)

        timer.activeProject = nil
        timer.activeSession = nil
        let paused = Session(project: project, date: .now, startTime: .now, endTime: .now,
                             durationSeconds: 5076, category: .personal, status: .paused)
        try dependencies.sessionRepository.insert(paused)
        model.reload()
        try capture("notch-paused", model: model, dependencies: dependencies, output: output)

        paused.status = .completed
        try dependencies.sessionRepository.update(paused)
        model.reload()
        try capture("notch-idle", model: model, dependencies: dependencies, output: output)

        model.query = "zzzz"
        try capture("notch-search-empty", model: model, dependencies: dependencies, output: output)
        model.query = ""

        project.name = "Projeto com nome bastante longo que deve terminar com reticências"
        project.client = "Cliente com identificação extensa para validar truncamento"
        try dependencies.projectRepository.update(project)
        timer.activeProject = project
        timer.activeSession = Session(project: project, date: .now, startTime: .now, category: .personal)
        timer.elapsed = 360000
        model.reload()
        try capture("notch-long-content", model: model, dependencies: dependencies, output: output)
    }

    private func capture(_ name: String, model: NotchPanelViewModel,
                         dependencies: DependencyContainer, output: String) throws {
        let content = NotchPanelView(viewModel: model, isPinned: .constant(false), registersShortcuts: false)
            .environment(\.dependencies, dependencies)
            .environment(\.colorScheme, .dark)
        let contentHost = NSHostingView(rootView: content)
        let height = ceil(contentHost.fittingSize.height) + 32
        let size = CGSize(width: NotchPanelMetrics.expandedWidth, height: height)
        let root = NotchContentView(isExpanded: true, notchWidth: 180, notchHeight: 32,
                                   expandedContent: { content })
            .frame(width: size.width, height: size.height)
        // Fundo de contraste e margem mostram os ombros e os cantos transparentes.
        let canvas = root.padding(.horizontal, 32)
            .background(Color(red: 0.30, green: 0.38, blue: 0.47))
        let host = NSHostingView(rootView: canvas)
        host.frame = NSRect(origin: .zero, size: CGSize(width: size.width + 64, height: size.height))
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: output).appendingPathComponent("\(name).png"))
        #expect(size.width == 368)
        #expect(size.height < 700)
        #expect(png.count > 3000)
    }
}

@MainActor
private final class NotchPreviewTimer: TimerServiceProtocol {
    var activeSession: Session?
    var activeProject: Project?
    var elapsed: TimeInterval = 0
    var isRunning: Bool { activeSession != nil }
    func start(project: Project) throws {}
    func pause() throws {}
    func resume() throws {}
    func stop() throws {}
    func addManualSession(project: Project, startTime: Date, endTime: Date, note: String) throws {}
}
