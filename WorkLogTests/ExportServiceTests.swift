import Testing
import Foundation
@testable import WorkLog

struct ExportServiceTests {
    @Test func csvExportContainsHeadersAndRows() throws {
        let service = ExportService()
        let table = ExportTable(title: "Relatório", headers: ["A", "B"], rows: [["1", "2"]])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".csv")
        defer { try? FileManager.default.removeItem(at: url) }

        try service.export(table, format: .csv, to: url)

        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content.contains("A,B"))
        #expect(content.contains("1,2"))
    }

    @Test func csvEscapesFieldsWithCommas() throws {
        let service = ExportService()
        let table = ExportTable(title: "Relatório", headers: ["A"], rows: [["value, with comma"]])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".csv")
        defer { try? FileManager.default.removeItem(at: url) }

        try service.export(table, format: .csv, to: url)

        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content.contains("\"value, with comma\""))
    }

    @Test func excelExportProducesValidSpreadsheetXML() throws {
        let service = ExportService()
        let table = ExportTable(title: "Relatório", headers: ["A"], rows: [["1"]])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".xml")
        defer { try? FileManager.default.removeItem(at: url) }

        try service.export(table, format: .excel, to: url)

        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content.contains("<Workbook"))
        #expect(content.contains("Relatório"))
    }

    @Test func pdfExportProducesNonEmptyFile() throws {
        let service = ExportService()
        let table = ExportTable(title: "Relatório", headers: ["A"], rows: [["1"]])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }

        try service.export(table, format: .pdf, to: url)

        let data = try Data(contentsOf: url)
        #expect(!data.isEmpty)
    }

    @Test func pdfExportWrapsManyRowsAcrossPages() throws {
        let service = ExportService()
        let rows = (0..<200).map { ["Linha \($0)", "Um texto bem longo para forçar quebra de página \($0)"] }
        let table = ExportTable(title: "Relatório", headers: ["A", "B"], rows: rows)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }

        try service.export(table, format: .pdf, to: url)

        let data = try Data(contentsOf: url)
        #expect(!data.isEmpty)
    }

    @Test func invoiceExportProducesNonEmptyFile() throws {
        let service = ExportService()
        let document = InvoiceDocument(
            issuerName: "Murilo Ribeiro",
            issuerDetails: "CPF 000.000.000-00\nPIX: murilo@example.com",
            invoiceNumber: "FAT-0001",
            issueDate: .now,
            client: "Acme",
            periodStart: .now,
            periodEnd: .now,
            lineItems: [InvoiceLineItem(date: .now, projectName: "Site", durationSeconds: 3600, value: 100)],
            totalDurationSeconds: 3600,
            totalValue: 100,
            notes: ""
        )
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }

        try service.exportInvoice(document, to: url)

        let data = try Data(contentsOf: url)
        #expect(!data.isEmpty)
    }
}
