import AppKit
import CoreText

/// Alinhamento de uma coluna dentro de uma tabela PDF.
enum PDFColumnAlignment {
    case leading
    case trailing
}

struct PDFColumn {
    let title: String
    let weight: CGFloat
    let alignment: PDFColumnAlignment

    init(title: String, weight: CGFloat = 1, alignment: PDFColumnAlignment = .leading) {
        self.title = title
        self.weight = weight
        self.alignment = alignment
    }
}

/// Uma linha de texto livre desenhada antes da tabela (cabeçalho/letterhead).
struct PDFTextLine {
    let text: String
    let font: NSFont
    let color: NSColor
    let alignment: PDFColumnAlignment
    let spacingAfter: CGFloat

    init(_ text: String, font: NSFont, color: NSColor = .black, alignment: PDFColumnAlignment = .leading, spacingAfter: CGFloat = 4) {
        self.text = text
        self.font = font
        self.color = color
        self.alignment = alignment
        self.spacingAfter = spacingAfter
    }
}

/// Gera documentos PDF com tabelas paginadas, quebra de texto e grade.
/// Desenha diretamente via Core Text no sistema de coordenadas nativo do
/// `CGContext` (origem no canto inferior esquerdo), evitando a ambiguidade de
/// contextos "flipped" do AppKit.
enum PDFTableRenderer {
    static let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842) // A4 em pontos
    static let margin: CGFloat = 40

    private static let cellPaddingX: CGFloat = 6
    private static let cellPaddingY: CGFloat = 5
    private static let minRowHeight: CGFloat = 20
    private static let headerBackground = NSColor(white: 0.88, alpha: 1)
    private static let rowBandBackground = NSColor(white: 0.96, alpha: 1)
    private static let gridColor = NSColor(white: 0.78, alpha: 1)
    private static let headerFont = NSFont.boldSystemFont(ofSize: 10.5)
    private static let bodyFont = NSFont.systemFont(ofSize: 9.5)
    private static let footerFont = NSFont.systemFont(ofSize: 8)

    static func makeContext(url: URL) throws -> CGContext {
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            throw ExportError.pdfContextCreationFailed
        }
        return context
    }

    /// Desenha um documento completo: linhas de cabeçalho livres seguidas de uma
    /// tabela paginada com grade, cabeçalho sombreado e faixas alternadas.
    static func render(
        context: CGContext,
        headerLines: [PDFTextLine],
        columns: [PDFColumn],
        rows: [[String]],
        footerNote: String,
        boldRowIndices: Set<Int> = []
    ) {
        let contentWidth = pageRect.width - margin * 2
        let widths = columnWidths(for: columns, totalWidth: contentWidth)

        var pageIndex = 0
        var cursorY: CGFloat = 0

        func drawHeaderLines() {
            for line in headerLines {
                let height = heightForWrapped(line.text, font: line.font, width: contentWidth)
                let rect = CGRect(x: margin, y: cursorY - height, width: contentWidth, height: height)
                drawWrapped(line.text, font: line.font, color: line.color, alignment: line.alignment, in: rect, context: context)
                cursorY -= height + line.spacingAfter
            }
            cursorY -= 6
        }

        func drawTableHeader() {
            let height = columns.enumerated().map { index, column in
                heightForWrapped(column.title, font: headerFont, width: widths[index] - cellPaddingX * 2)
            }.max().map { $0 + cellPaddingY * 2 } ?? minRowHeight
            let rowTop = cursorY

            context.setFillColor(headerBackground.cgColor)
            context.fill(CGRect(x: margin, y: rowTop - height, width: contentWidth, height: height))

            var x = margin
            for (index, column) in columns.enumerated() {
                let cellRect = CGRect(x: x + cellPaddingX, y: rowTop - height + cellPaddingY, width: widths[index] - cellPaddingX * 2, height: height - cellPaddingY * 2)
                drawWrapped(column.title, font: headerFont, color: .black, alignment: column.alignment, in: cellRect, context: context)
                x += widths[index]
            }
            drawGrid(top: rowTop, height: height, widths: widths, context: context)
            cursorY = rowTop - height
        }

        func drawFooter() {
            let text = "\(footerNote) — Página \(pageIndex)"
            let height = heightForWrapped(text, font: footerFont, width: contentWidth)
            let rect = CGRect(x: margin, y: margin - height, width: contentWidth, height: height)
            drawWrapped(text, font: footerFont, color: .darkGray, alignment: .leading, in: rect, context: context)
        }

        func startPage() {
            pageIndex += 1
            context.beginPDFPage(nil)
            cursorY = pageRect.height - margin
            if pageIndex == 1 {
                drawHeaderLines()
            }
            drawTableHeader()
        }

        func endPage() {
            drawFooter()
            context.endPDFPage()
        }

        startPage()

        for (index, row) in rows.enumerated() {
            let rowFont = boldRowIndices.contains(index) ? NSFont.boldSystemFont(ofSize: bodyFont.pointSize) : bodyFont
            let height = rowHeight(for: row, columns: columns, widths: widths, font: rowFont)
            if cursorY - height < margin + 24 {
                endPage()
                startPage()
            }
            let rowTop = cursorY
            if boldRowIndices.contains(index) {
                context.setFillColor(headerBackground.cgColor)
                context.fill(CGRect(x: margin, y: rowTop - height, width: contentWidth, height: height))
            } else if index % 2 == 1 {
                context.setFillColor(rowBandBackground.cgColor)
                context.fill(CGRect(x: margin, y: rowTop - height, width: contentWidth, height: height))
            }

            var x = margin
            for (columnIndex, column) in columns.enumerated() {
                let value = columnIndex < row.count ? row[columnIndex] : ""
                let cellRect = CGRect(x: x + cellPaddingX, y: rowTop - height + cellPaddingY, width: widths[columnIndex] - cellPaddingX * 2, height: height - cellPaddingY * 2)
                drawWrapped(value, font: rowFont, color: .black, alignment: column.alignment, in: cellRect, context: context)
                x += widths[columnIndex]
            }
            drawGrid(top: rowTop, height: height, widths: widths, context: context)
            cursorY = rowTop - height
        }

        endPage()
    }

    // MARK: - Layout

    private static func columnWidths(for columns: [PDFColumn], totalWidth: CGFloat) -> [CGFloat] {
        let totalWeight = columns.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return columns.map { _ in totalWidth / CGFloat(max(columns.count, 1)) } }
        return columns.map { totalWidth * $0.weight / totalWeight }
    }

    private static func rowHeight(for row: [String], columns: [PDFColumn], widths: [CGFloat], font: NSFont) -> CGFloat {
        let height = columns.enumerated().map { index, _ -> CGFloat in
            let value = index < row.count ? row[index] : ""
            return heightForWrapped(value, font: font, width: widths[index] - cellPaddingX * 2)
        }.max() ?? 0
        return max(minRowHeight, height + cellPaddingY * 2)
    }

    private static func drawGrid(top: CGFloat, height: CGFloat, widths: [CGFloat], context: CGContext) {
        context.setStrokeColor(gridColor.cgColor)
        context.setLineWidth(0.5)

        var x = margin
        for width in widths {
            context.stroke(CGRect(x: x, y: top - height, width: 0.5, height: height))
            x += width
        }
        context.stroke(CGRect(x: x, y: top - height, width: 0.5, height: height))
        context.stroke(CGRect(x: margin, y: top - height, width: x - margin, height: 0.5))
        context.stroke(CGRect(x: margin, y: top, width: x - margin, height: 0.5))
    }

    // MARK: - Core Text

    private static func heightForWrapped(_ text: String, font: NSFont, width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        let attributed = NSAttributedString(string: text.isEmpty ? " " : text, attributes: [.font: font])
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: 0),
            nil,
            CGSize(width: width, height: .greatestFiniteMagnitude),
            nil
        )
        return ceil(size.height)
    }

    private static func drawWrapped(_ text: String, font: NSFont, color: NSColor, alignment: PDFColumnAlignment, in rect: CGRect, context: CGContext) {
        guard rect.width > 0, rect.height > 0 else { return }
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment == .leading ? .left : .right
        paragraphStyle.lineBreakMode = .byWordWrapping
        let attributed = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle,
        ])
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: rect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        context.saveGState()
        CTFrameDraw(frame, context)
        context.restoreGState()
    }
}
