import Foundation
import CoreGraphics

/// Propriedades que podem ser incluídas em um relatório exportado.
/// A ordem dos cases define a ordem padrão das colunas.
enum ReportColumn: String, CaseIterable, Identifiable, Codable {
    case project
    case client
    case date
    case startTime
    case endTime
    case duration
    case sessionCount
    case category
    case status
    case value
    case note
    case tags
    case description

    var id: String { rawValue }

    var header: String {
        switch self {
        case .project: return "Projeto"
        case .client: return "Cliente"
        case .date: return "Data"
        case .startTime: return "Início"
        case .endTime: return "Fim"
        case .duration: return "Duração"
        case .sessionCount: return "Nº de sessões"
        case .category: return "Categoria"
        case .status: return "Status"
        case .value: return "Valor"
        case .note: return "Observação"
        case .tags: return "Tags"
        case .description: return "Descrição"
        }
    }

    /// Colunas selecionadas por padrão (equivalente ao relatório detalhado atual).
    static let defaultSelection: [ReportColumn] = [
        .project, .client, .date, .startTime, .endTime, .duration, .category, .status, .value, .note,
    ]

    /// Alinhamento usado na exportação em PDF: colunas numéricas ficam à direita.
    var pdfAlignment: PDFColumnAlignment {
        switch self {
        case .duration, .value, .sessionCount:
            return .trailing
        default:
            return .leading
        }
    }

    /// Peso relativo de largura usado na exportação em PDF.
    var pdfWeight: CGFloat {
        switch self {
        case .note, .description:
            return 2
        case .project, .client, .tags:
            return 1.4
        default:
            return 1
        }
    }

    func value(from row: ReportRow) -> String {
        switch self {
        case .project:
            return row.projectName
        case .client:
            return row.client
        case .date:
            return DateFormatter.shortDate.string(from: row.date)
        case .startTime:
            return DateFormatter.shortTime.string(from: row.startTime)
        case .endTime:
            return row.endTime.map { DateFormatter.shortTime.string(from: $0) } ?? "—"
        case .duration:
            return row.durationSeconds.formattedClock(showSeconds: true)
        case .sessionCount:
            return String(row.sessionCount)
        case .category:
            return row.category.displayName
        case .status:
            return row.status.displayName
        case .value:
            return row.estimatedValue.currencyFormatted
        case .note:
            return row.note
        case .tags:
            return row.tags.joined(separator: ", ")
        case .description:
            return row.descriptionText
        }
    }
}
