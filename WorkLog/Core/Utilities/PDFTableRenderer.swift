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

/// Uma linha de texto livre desenhada no cabeçalho (letterhead).
struct PDFTextLine {
    let text: String
    let font: NSFont
    let color: NSColor
    let alignment: PDFColumnAlignment
    let tracking: CGFloat
    let spacingAfter: CGFloat

    init(_ text: String, font: NSFont, color: NSColor = PDFTableRenderer.ink, alignment: PDFColumnAlignment = .leading, tracking: CGFloat = 0, spacingAfter: CGFloat = 4) {
        self.text = text
        self.font = font
        self.color = color
        self.alignment = alignment
        self.tracking = tracking
        self.spacingAfter = spacingAfter
    }
}

/// Gera documentos PDF com um letterhead de duas colunas e uma tabela paginada
/// em estilo "ledger": cabeçalho com régua de destaque, linhas separadas por
/// finas hairlines, sem grade vertical nem zebra pesada, e uma linha de total
/// evidenciada. Desenha via Core Text no sistema de coordenadas nativo do
/// `CGContext` (origem no canto inferior esquerdo).
enum PDFTableRenderer {
    static let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842) // A4 em pontos
    static let margin: CGFloat = 48

    // MARK: Paleta

    /// Azul-índigo sóbrio usado como cor de marca nos PDFs (réguas, rótulos, total).
    static let accent = NSColor(red: 0.17, green: 0.24, blue: 0.42, alpha: 1)
    /// Cor de corpo de texto (quase preto) — contraste alto para leitura.
    static let ink = NSColor(white: 0.13, alpha: 1)
    /// Texto secundário (rótulos, metadados).
    static let muted = NSColor(white: 0.42, alpha: 1)

    private static let hairline = NSColor(white: 0.88, alpha: 1)
    private static let totalTint = accent.withAlphaComponent(0.06)

    private static let cellPaddingX: CGFloat = 4
    private static let cellPaddingY: CGFloat = 9
    private static let minRowHeight: CGFloat = 26
    private static let headerFont = NSFont.systemFont(ofSize: 8.5, weight: .semibold)
    private static let bodyFont = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .regular)
    private static let totalFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)
    private static let footerFont = NSFont.systemFont(ofSize: 8)

    /// Altura do logo desenhado no canto superior direito da primeira página.
    private static let logoHeight: CGFloat = 42

    static func makeContext(url: URL) throws -> CGContext {
        guard let consumer = CGDataConsumer(url: url as CFURL) else {
            throw ExportError.pdfContextCreationFailed
        }
        // Fixa o media box em A4 (`pageRect`). Sem isto, o PDF assume o padrão
        // US Letter (612×792) e o conteúdo desenhado no topo — como o título —
        // fica acima da borda real da página e aparece cortado.
        var mediaBox = pageRect
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw ExportError.pdfContextCreationFailed
        }
        return context
    }

    /// Desenha um documento completo.
    ///
    /// - Parameters:
    ///   - leftHeader: bloco esquerdo do letterhead (emissor / título).
    ///   - rightHeader: bloco direito, alinhado à direita (metadados da nota).
    ///   - subHeader: bloco de largura total abaixo da régua (ex.: "Faturado a").
    ///   - footerNote: observação livre exibida no rodapé (à esquerda).
    ///   - totalRowIndex: índice da linha de total, destacada visualmente.
    ///   - logo: imagem opcional no canto superior direito da 1ª página.
    static func render(
        context: CGContext,
        leftHeader: [PDFTextLine],
        rightHeader: [PDFTextLine] = [],
        subHeader: [PDFTextLine] = [],
        columns: [PDFColumn],
        rows: [[String]],
        footerNote: String,
        totalRowIndex: Int? = nil,
        brandName: String = "WorkLog",
        logo: NSImage? = nil
    ) {
        let contentWidth = pageRect.width - margin * 2
        let widths = columnWidths(for: columns, totalWidth: contentWidth)
        let leftColWidth = contentWidth * 0.56
        let rightColX = margin + contentWidth * 0.58
        let rightColWidth = margin + contentWidth - rightColX

        var pageIndex = 0
        var cursorY: CGFloat = 0

        func drawStack(_ lines: [PDFTextLine], x: CGFloat, width: CGFloat, startY: CGFloat) -> CGFloat {
            var y = startY
            for line in lines {
                let h = heightForWrapped(line.text, font: line.font, width: width, tracking: line.tracking)
                let rect = CGRect(x: x, y: y - h, width: width, height: h)
                drawWrapped(line.text, font: line.font, color: line.color, alignment: line.alignment, tracking: line.tracking, in: rect, context: context)
                y -= h + line.spacingAfter
            }
            return y
        }

        func drawRule(at y: CGFloat, x: CGFloat, width: CGFloat, color: NSColor, thickness: CGFloat) {
            context.setFillColor(color.cgColor)
            context.fill(CGRect(x: x, y: y - thickness, width: width, height: thickness))
        }

        func drawLogo(topY: CGFloat) -> CGFloat {
            guard let logo, logo.size.width > 0, logo.size.height > 0,
                  let cgImage = logo.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return topY }
            let aspect = logo.size.width / logo.size.height
            let height = logoHeight
            let width = height * aspect
            // Marca da carta no topo-esquerda, liderando o letterhead.
            let rect = CGRect(x: margin, y: topY - height, width: width, height: height)
            // Cantos arredondados para suavizar o recorte do asset.
            context.saveGState()
            let clip = CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil)
            context.addPath(clip)
            context.clip()
            context.draw(cgImage, in: rect)
            context.restoreGState()
            return topY - height - 14
        }

        func drawLetterhead() {
            let topY = cursorY
            // Coluna esquerda: logo (se houver) liderando o bloco do emissor/título.
            let leftTop = drawLogo(topY: topY)
            let leftBottom = drawStack(leftHeader, x: margin, width: leftColWidth, startY: leftTop)
            // Coluna direita: metadados alinhados ao topo da página.
            let rightBottom = drawStack(rightHeader, x: rightColX, width: rightColWidth, startY: topY)

            var bottom = min(leftBottom, rightBottom)
            bottom -= 14
            drawRule(at: bottom, x: margin, width: contentWidth, color: accent, thickness: 1)
            bottom -= 16

            if !subHeader.isEmpty {
                bottom = drawStack(subHeader, x: margin, width: contentWidth, startY: bottom)
                bottom -= 14
            }
            cursorY = bottom
        }

        func drawTableHeader() {
            let titles = columns.map { $0.title.uppercased() }
            let height = columns.enumerated().map { index, _ in
                heightForWrapped(titles[index], font: headerFont, width: widths[index] - cellPaddingX * 2, tracking: 0.6)
            }.max().map { $0 + cellPaddingY * 2 } ?? minRowHeight
            let rowTop = cursorY

            var x = margin
            for (index, column) in columns.enumerated() {
                let cellRect = CGRect(x: x + cellPaddingX, y: rowTop - height + cellPaddingY, width: widths[index] - cellPaddingX * 2, height: height - cellPaddingY * 2)
                drawWrapped(titles[index], font: headerFont, color: accent, alignment: column.alignment, tracking: 0.6, in: cellRect, context: context)
                x += widths[index]
            }
            drawRule(at: rowTop - height, x: margin, width: contentWidth, color: accent, thickness: 1.2)
            cursorY = rowTop - height
        }

        func drawFooter() {
            let bandTop = margin - 4
            drawRule(at: bandTop, x: margin, width: contentWidth, color: hairline, thickness: 0.5)
            let height = heightForWrapped(brandName, font: footerFont, width: contentWidth, tracking: 0)
            let rect = CGRect(x: margin, y: bandTop - 6 - height, width: contentWidth, height: height)
            if !footerNote.isEmpty {
                drawWrapped(footerNote, font: footerFont, color: muted, alignment: .leading, tracking: 0, in: rect, context: context)
            }
            drawWrapped("\(brandName) · Página \(pageIndex)", font: footerFont, color: muted, alignment: .trailing, tracking: 0, in: rect, context: context)
        }

        func startPage() {
            pageIndex += 1
            context.beginPDFPage(nil)
            cursorY = pageRect.height - margin
            if pageIndex == 1 {
                drawLetterhead()
            }
            drawTableHeader()
        }

        func endPage() {
            drawFooter()
            context.endPDFPage()
        }

        startPage()

        for (index, row) in rows.enumerated() {
            let isTotal = index == totalRowIndex
            let rowFont = isTotal ? totalFont : bodyFont
            let height = rowHeight(for: row, columns: columns, widths: widths, font: rowFont)
            if cursorY - height < margin + 28 {
                endPage()
                startPage()
            }
            let rowTop = cursorY

            if isTotal {
                context.setFillColor(totalTint.cgColor)
                context.fill(CGRect(x: margin, y: rowTop - height, width: contentWidth, height: height))
                drawRule(at: rowTop, x: margin, width: contentWidth, color: accent, thickness: 1.2)
            }

            var x = margin
            for (columnIndex, column) in columns.enumerated() {
                let value = columnIndex < row.count ? row[columnIndex] : ""
                let cellRect = CGRect(x: x + cellPaddingX, y: rowTop - height + cellPaddingY, width: widths[columnIndex] - cellPaddingX * 2, height: height - cellPaddingY * 2)
                let color: NSColor = isTotal ? (column.alignment == .trailing ? accent : ink) : ink
                drawWrapped(value, font: rowFont, color: color, alignment: column.alignment, tracking: 0, in: cellRect, context: context)
                x += widths[columnIndex]
            }

            if isTotal {
                drawRule(at: rowTop - height, x: margin, width: contentWidth, color: accent, thickness: 1.2)
            } else {
                drawRule(at: rowTop - height, x: margin, width: contentWidth, color: hairline, thickness: 0.5)
            }
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
            return heightForWrapped(value, font: font, width: widths[index] - cellPaddingX * 2, tracking: 0)
        }.max() ?? 0
        return max(minRowHeight, height + cellPaddingY * 2)
    }

    // MARK: - Core Text

    private static func attributes(font: NSFont, color: NSColor = .black, alignment: PDFColumnAlignment = .leading, tracking: CGFloat = 0) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment == .leading ? .left : .right
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = 1.5
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle,
        ]
        if tracking != 0 { attrs[.kern] = tracking }
        return attrs
    }

    private static func heightForWrapped(_ text: String, font: NSFont, width: CGFloat, tracking: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        let attributed = NSAttributedString(string: text.isEmpty ? " " : text, attributes: attributes(font: font, tracking: tracking))
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

    private static func drawWrapped(_ text: String, font: NSFont, color: NSColor, alignment: PDFColumnAlignment, tracking: CGFloat, in rect: CGRect, context: CGContext) {
        guard rect.width > 0, rect.height > 0, !text.isEmpty else { return }
        let attributed = NSAttributedString(string: text, attributes: attributes(font: font, color: color, alignment: alignment, tracking: tracking))
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: rect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        context.saveGState()
        CTFrameDraw(frame, context)
        context.restoreGState()
    }
}
