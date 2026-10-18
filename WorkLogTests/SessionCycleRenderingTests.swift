import AppKit
import SwiftUI
import Testing
@testable import WorkLog

/// Capturas opt-in dos componentes reais, sem abrir ou alterar o banco do app.
@MainActor
struct SessionCycleRenderingTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["WORKLOG_CYCLE_PREVIEW_DIR"] != nil))
    func renderCycleStatesWithSyntheticData() throws {
        guard let output = ProcessInfo.processInfo.environment["WORKLOG_CYCLE_PREVIEW_DIR"] else { return }
        try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
        _ = NSApplication.shared
        let context = makeInMemoryContext()
        let repository = SessionRepository(modelContext: context)
        let project = Project(name: "Projeto de teste dos ciclos", client: "Dados sintéticos", dailyRate: 0, category: .work)
        context.insert(project)
        let start = Date(timeIntervalSince1970: 1_792_366_200) // 18/10, 23:30 UTC
        let periods: [SessionWorkPeriod] = [
            .init(start: start, end: start.addingTimeInterval(3_600)),
            .init(start: start.addingTimeInterval(5_400), end: start.addingTimeInterval(5_445))
        ]
        let session = Session(project: project, date: start, startTime: start,
            endTime: periods.last?.end, durationSeconds: 3_645, category: .work, status: .paused)
        session.workPeriods = periods
        try repository.insert(session)
        try capture("cycles-collapsed", content: SessionRowView(session: session), height: 110, output: output)
        try capture("cycles-expanded", content: SessionCycleDetailsView(periods: periods).padding(20), height: 320, output: output)

        let model = SessionFormViewModel(project: project, sessionRepository: repository, editing: session)
        try capture("cycles-editor", content: editor(model), height: 580, output: output)
        model.updateCycleEnd(at: 1, to: periods[1].start.addingTimeInterval(-1))
        try capture("cycles-editor-invalid", content: editor(model), height: 620, output: output)

        let running = Session(project: project, date: start, startTime: start,
            durationSeconds: 3_645, category: .work, status: .running)
        running.workPeriods = periods + [.init(start: start.addingTimeInterval(7_200), end: nil)]
        let runningModel = SessionFormViewModel(project: project, sessionRepository: repository, editing: running)
        try capture("cycles-running", content: editor(runningModel), height: 620, output: output)
    }

    private func editor(_ model: SessionFormViewModel) -> some View {
        Form {
            SessionPeriodFields(viewModel: model)
            Section("Observação") { Text("Sessão de teste com pausa entre os ciclos.") }
        }
        .formStyle(.grouped)
    }

    private func capture<Content: View>(_ name: String, content: Content, height: CGFloat, output: String) throws {
        let root = content
            .environment(\.locale, Locale(identifier: "pt_BR"))
            .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
            .environment(\.colorScheme, .light)
            .frame(width: 480, height: height)
            .background(Color.white)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: 480, height: height)
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: output).appendingPathComponent("\(name).png"))
        #expect(png.count > 3_000)
    }
}
