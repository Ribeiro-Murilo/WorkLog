import Foundation
import AppKit
import CoreText

enum ExportFormat: String, CaseIterable, Identifiable {
    case csv
    case excel
    case pdf

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .csv: return "csv"
        case .excel: return "xml"
        case .pdf: return "pdf"
        }
    }

    var displayName: String {
        switch self {
        case .csv: return "CSV"
        case .excel: return "Excel"
        case .pdf: return "PDF"
        }
    }
}

struct ExportTable {
    let title: String
    let headers: [String]
    let rows: [[String]]
    let alignments: [PDFColumnAlignment]
    let weights: [CGFloat]

    init(title: String, headers: [String], rows: [[String]], alignments: [PDFColumnAlignment]? = nil, weights: [CGFloat]? = nil) {
        self.title = title
        self.headers = headers
        self.rows = rows
        self.alignments = alignments ?? headers.map { _ in .leading }
        self.weights = weights ?? headers.map { _ in 1 }
    }
}

/// Documento pronto para virar uma nota de faturamento em PDF.
struct InvoiceDocument {
    let issuerName: String
    let issuerDetails: String
    let invoiceNumber: String
    let issueDate: Date
    let client: String
    let periodStart: Date
    let periodEnd: Date
    let lineItems: [InvoiceLineItem]
    let totalDurationSeconds: TimeInterval
    let totalValue: Decimal
    let notes: String
}

protocol ExportServiceProtocol {
    func export(_ table: ExportTable, format: ExportFormat, to url: URL, includeLogo: Bool) throws
    func exportInvoice(_ document: InvoiceDocument, to url: URL, includeLogo: Bool) throws
}

extension ExportServiceProtocol {
    func export(_ table: ExportTable, format: ExportFormat, to url: URL) throws {
        try export(table, format: format, to: url, includeLogo: false)
    }

    func exportInvoice(_ document: InvoiceDocument, to url: URL) throws {
        try exportInvoice(document, to: url, includeLogo: false)
    }
}

struct ExportService: ExportServiceProtocol {
    /// Logo do app usado nos PDFs quando o usuário ativa a opção.
    private func pdfLogo(_ include: Bool) -> NSImage? {
        include ? NSImage(named: "Logo") : nil
    }

    func export(_ table: ExportTable, format: ExportFormat, to url: URL, includeLogo: Bool) throws {
        switch format {
        case .csv:
            try exportCSV(table, to: url)
        case .excel:
            try exportExcelXML(table, to: url)
        case .pdf:
            try exportPDF(table, to: url, includeLogo: includeLogo)
        }
    }

    // MARK: - CSV

    private func exportCSV(_ table: ExportTable, to url: URL) throws {
        var lines: [String] = [table.headers.map(csvField).joined(separator: ",")]
        for row in table.rows {
            lines.append(row.map(csvField).joined(separator: ","))
        }
        let content = lines.joined(separator: "\r\n")
        let bom = "\u{FEFF}"
        try (bom + content).write(to: url, atomically: true, encoding: .utf8)
    }

    private func csvField(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - Excel (SpreadsheetML 2003 XML — aberto nativamente pelo Excel)

    private func exportExcelXML(_ table: ExportTable, to url: URL) throws {
        var xml = """
        <?xml version="1.0"?>
        <?mso-application progid="Excel.Sheet"?>
        <Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet"
         xmlns:o="urn:schemas-microsoft-com:office:office"
         xmlns:x="urn:schemas-microsoft-com:office:excel"
         xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">
         <Worksheet ss:Name="\(xmlEscape(table.title))">
          <Table>
        """

        xml += "\n   <Row>"
        for header in table.headers {
            xml += "<Cell><Data ss:Type=\"String\">\(xmlEscape(header))</Data></Cell>"
        }
        xml += "</Row>"

        for row in table.rows {
            xml += "\n   <Row>"
            for value in row {
                xml += "<Cell><Data ss:Type=\"String\">\(xmlEscape(value))</Data></Cell>"
            }
            xml += "</Row>"
        }

        xml += """

          </Table>
         </Worksheet>
        </Workbook>
        """

        try xml.write(to: url, atomically: true, encoding: .utf8)
    }

    private func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - PDF

    private func exportPDF(_ table: ExportTable, to url: URL, includeLogo: Bool) throws {
        let context = try PDFTableRenderer.makeContext(url: url)

        let titleFont = NSFont.boldSystemFont(ofSize: 18)
        let subtitleFont = NSFont.systemFont(ofSize: 9)
        let generatedAt = DateFormatter.shortDate.string(from: .now) + " às " + DateFormatter.shortTime.string(from: .now)

        let columns = table.headers.enumerated().map { index, header in
            PDFColumn(
                title: header,
                weight: index < table.weights.count ? table.weights[index] : 1,
                alignment: index < table.alignments.count ? table.alignments[index] : .leading
            )
        }

        PDFTableRenderer.render(
            context: context,
            leftHeader: [
                PDFTextLine(table.title, font: titleFont, color: PDFTableRenderer.ink, spacingAfter: 3),
                PDFTextLine("Gerado em \(generatedAt)", font: subtitleFont, color: PDFTableRenderer.muted, spacingAfter: 0),
            ],
            columns: columns,
            rows: table.rows,
            footerNote: "",
            logo: pdfLogo(includeLogo)
        )

        context.closePDF()
    }

    // MARK: - Invoice PDF

    func exportInvoice(_ document: InvoiceDocument, to url: URL, includeLogo: Bool) throws {
        let context = try PDFTableRenderer.makeContext(url: url)

        let ink = PDFTableRenderer.ink
        let muted = PDFTableRenderer.muted
        let accent = PDFTableRenderer.accent

        let issuerNameFont = NSFont.boldSystemFont(ofSize: 16)
        let issuerDetailsFont = NSFont.systemFont(ofSize: 9)
        let labelFont = NSFont.systemFont(ofSize: 8.5, weight: .semibold)
        let invoiceNumberFont = NSFont.boldSystemFont(ofSize: 15)
        let metaFont = NSFont.systemFont(ofSize: 9.5)
        let clientNameFont = NSFont.boldSystemFont(ofSize: 13)

        // Coluna esquerda: emissor.
        var leftHeader: [PDFTextLine] = []
        if !document.issuerName.isEmpty {
            leftHeader.append(PDFTextLine(document.issuerName, font: issuerNameFont, color: ink, spacingAfter: 4))
        }
        if !document.issuerDetails.isEmpty {
            leftHeader.append(PDFTextLine(document.issuerDetails, font: issuerDetailsFont, color: muted, spacingAfter: 0))
        }

        // Coluna direita: identificação da nota, alinhada à direita.
        let rightHeader: [PDFTextLine] = [
            PDFTextLine("NOTA DE FATURAMENTO", font: labelFont, color: accent, alignment: .trailing, tracking: 1, spacingAfter: 4),
            PDFTextLine(document.invoiceNumber, font: invoiceNumberFont, color: ink, alignment: .trailing, spacingAfter: 6),
            PDFTextLine("Emitida em \(DateFormatter.shortDate.string(from: document.issueDate))", font: metaFont, color: muted, alignment: .trailing, spacingAfter: 2),
            PDFTextLine(
                "Período: \(DateFormatter.shortDate.string(from: document.periodStart)) a \(DateFormatter.shortDate.string(from: document.periodEnd))",
                font: metaFont, color: muted, alignment: .trailing, spacingAfter: 0
            ),
        ]

        // Bloco de largura total abaixo da régua: destinatário.
        let subHeader: [PDFTextLine] = [
            PDFTextLine("FATURADO A", font: labelFont, color: accent, tracking: 1, spacingAfter: 3),
            PDFTextLine(document.client, font: clientNameFont, color: ink, spacingAfter: 0),
        ]

        let columns = [
            PDFColumn(title: "Data", weight: 1, alignment: .leading),
            PDFColumn(title: "Projeto", weight: 1.6, alignment: .leading),
            PDFColumn(title: "Duração", weight: 1, alignment: .trailing),
            PDFColumn(title: "Valor", weight: 1, alignment: .trailing),
        ]

        var rows = document.lineItems.map { item in
            [
                DateFormatter.shortDate.string(from: item.date),
                item.projectName,
                item.durationSeconds.formattedClock(showSeconds: false),
                item.value.currencyFormatted,
            ]
        }
        rows.append([
            "", "Total",
            document.totalDurationSeconds.formattedClock(showSeconds: false),
            document.totalValue.currencyFormatted,
        ])

        PDFTableRenderer.render(
            context: context,
            leftHeader: leftHeader,
            rightHeader: rightHeader,
            subHeader: subHeader,
            columns: columns,
            rows: rows,
            footerNote: document.notes,
            totalRowIndex: rows.count - 1,
            logo: pdfLogo(includeLogo)
        )

        context.closePDF()
    }
}

enum ExportError: LocalizedError {
    case pdfContextCreationFailed

    var errorDescription: String? {
        switch self {
        case .pdfContextCreationFailed: return "Não foi possível criar o documento PDF."
        }
    }
}
