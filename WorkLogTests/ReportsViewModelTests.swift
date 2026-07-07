import Testing
import Foundation
@testable import WorkLog

@MainActor
struct ReportsViewModelTests {
    private func makeSession(
        project: Project,
        date: Date,
        durationSeconds: TimeInterval,
        note: String = ""
    ) -> Session {
        Session(
            project: project,
            date: date,
            startTime: date,
            endTime: date.addingTimeInterval(durationSeconds),
            durationSeconds: durationSeconds,
            note: note,
            category: .work,
            status: .completed
        )
    }

    @Test func groupingByProjectAndDaySumsDurationAndValue() throws {
        let vm = ReportsViewModel(
            sessionRepository: SessionRepository(modelContext: makeInMemoryContext()),
            exportService: ExportService()
        )
        let project = Project(name: "Alpha", client: "Cliente", dailyRate: 0, category: .work)
        let day = Calendar.current.startOfDay(for: .now)

        vm.grouping = .byProjectAndDay
        vm.setSessionsForTesting([
            makeSession(project: project, date: day.addingTimeInterval(3600), durationSeconds: 1800, note: "manhã"),
            makeSession(project: project, date: day.addingTimeInterval(7200), durationSeconds: 1200, note: "tarde"),
        ])

        let rows = vm.reportRows()
        #expect(rows.count == 1)
        #expect(rows[0].durationSeconds == 3000)
        #expect(rows[0].sessionCount == 2)
        #expect(rows[0].note.contains("manhã"))
        #expect(rows[0].note.contains("tarde"))
    }

    @Test func detailedGroupingKeepsOneRowPerSession() throws {
        let vm = ReportsViewModel(
            sessionRepository: SessionRepository(modelContext: makeInMemoryContext()),
            exportService: ExportService()
        )
        let project = Project(name: "Alpha", client: "Cliente", dailyRate: 0, category: .work)
        let day = Calendar.current.startOfDay(for: .now)

        vm.grouping = .detailed
        vm.setSessionsForTesting([
            makeSession(project: project, date: day, durationSeconds: 1800),
            makeSession(project: project, date: day, durationSeconds: 1200),
        ])

        #expect(vm.reportRows().count == 2)
    }

    @Test func exportTableRespectsColumnSelectionAndOrder() throws {
        let vm = ReportsViewModel(
            sessionRepository: SessionRepository(modelContext: makeInMemoryContext()),
            exportService: ExportService()
        )
        let project = Project(name: "Alpha", client: "Cliente", dailyRate: 0, category: .work)
        vm.setSessionsForTesting([makeSession(project: project, date: .now, durationSeconds: 60)])
        vm.selectedColumns = [.project, .duration]

        let table = vm.exportTable()
        #expect(table.headers == ["Projeto", "Duração"])
        #expect(table.rows[0].count == 2)
        #expect(table.rows[0][0] == "Alpha")
    }
}
