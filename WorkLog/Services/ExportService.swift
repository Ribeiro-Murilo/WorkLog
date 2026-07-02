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
}

protocol ExportServiceProtocol {
    func export(_ table: ExportTable, format: ExportFormat, to url: URL) throws
}

struct ExportService: ExportServiceProtocol {
    func export(_ table: ExportTable, format: ExportFormat, to url: URL) throws {
        switch format {
        case .csv:
            try exportCSV(table, to: url)
        case .excel:
            try exportExcelXML(table, to: url)
        case .pdf:
            try exportPDF(table, to: url)
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

    private func exportPDF(_ table: ExportTable, to url: URL) throws {
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842) // A4 em pontos
        let margin: CGFloat = 36
        let lineHeight: CGFloat = 18

        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            throw ExportError.pdfContextCreationFailed
        }

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 16)
        ]
        let headerAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 11)
        ]
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10)
        ]

        let columnWidth = (pageRect.width - margin * 2) / CGFloat(max(table.headers.count, 1))

        func drawLine(_ columns: [String], attributes: [NSAttributedString.Key: Any], at y: CGFloat) {
            NSGraphicsContext.saveGraphicsState()
            let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.current = nsContext
            for (index, text) in columns.enumerated() {
                let x = margin + CGFloat(index) * columnWidth
                let string = NSAttributedString(string: text, attributes: attributes)
                string.draw(at: CGPoint(x: x, y: y))
            }
            NSGraphicsContext.restoreGraphicsState()
        }

        var cursorY = pageRect.height - margin
        context.beginPDFPage(nil)
        drawLine([table.title], attributes: titleAttributes, at: cursorY)
        cursorY -= lineHeight * 2
        drawLine(table.headers, attributes: headerAttributes, at: cursorY)
        cursorY -= lineHeight

        for row in table.rows {
            if cursorY < margin {
                context.endPDFPage()
                context.beginPDFPage(nil)
                cursorY = pageRect.height - margin
                drawLine(table.headers, attributes: headerAttributes, at: cursorY)
                cursorY -= lineHeight
            }
            drawLine(row, attributes: bodyAttributes, at: cursorY)
            cursorY -= lineHeight
        }

        context.endPDFPage()
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
