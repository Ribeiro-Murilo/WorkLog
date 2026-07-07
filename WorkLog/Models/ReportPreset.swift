import Foundation
import SwiftData

/// Um "tipo de relatório" salvo: combinação nomeada de colunas e modo de agrupamento.
@Model
final class ReportPreset {
    var id: UUID = UUID()
    var name: String = ""
    /// Colunas selecionadas, armazenadas como `ReportColumn.rawValue` na ordem desejada.
    var columnsRaw: [String] = []
    /// Modo de agrupamento, armazenado como `ReportGrouping.rawValue`.
    var groupingRaw: String = ReportGrouping.detailed.rawValue
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(name: String, columns: [ReportColumn], grouping: ReportGrouping) {
        self.id = UUID()
        self.name = name
        self.columnsRaw = columns.map(\.rawValue)
        self.groupingRaw = grouping.rawValue
        self.createdAt = .now
        self.updatedAt = .now
    }

    var columns: [ReportColumn] {
        columnsRaw.compactMap(ReportColumn.init(rawValue:))
    }

    var grouping: ReportGrouping {
        ReportGrouping(rawValue: groupingRaw) ?? .detailed
    }
}
