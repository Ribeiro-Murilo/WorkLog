import Foundation
import SwiftData

@Model
final class AppSettings {
    var id: UUID = UUID()
    var launchAtLogin: Bool = true
    var idleTimeoutMinutes: Int = 10
    var showSeconds: Bool = true
    var theme: AppTheme = AppTheme.system
    var timeFormat: TimeFormatPreference = TimeFormatPreference.twentyFourHour
    var displayMode: AppDisplayMode = AppDisplayMode.menuBar
    var lastBackupDate: Date?
    /// Nome exibido no cabeçalho das notas de faturamento.
    var invoiceIssuerName: String = ""
    /// Dados livres do emissor (CPF/CNPJ, PIX, endereço) exibidos abaixo do nome na nota.
    var invoiceIssuerDetails: String = ""
    /// Último número de fatura emitido. Cresce de forma monotônica e nunca é reaproveitado,
    /// mesmo que faturas sejam excluídas.
    var lastInvoiceNumber: Int = 0
    /// Quando ativo, inclui o logo do app no canto superior direito dos PDFs
    /// (relatórios e notas de faturamento). Opcional e desligado por padrão.
    var includeLogoInPDF: Bool = false
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(
        launchAtLogin: Bool = true,
        idleTimeoutMinutes: Int = 10,
        showSeconds: Bool = true,
        theme: AppTheme = .system,
        timeFormat: TimeFormatPreference = .twentyFourHour,
        displayMode: AppDisplayMode = .menuBar,
        invoiceIssuerName: String = "",
        invoiceIssuerDetails: String = ""
    ) {
        self.id = UUID()
        self.launchAtLogin = launchAtLogin
        self.idleTimeoutMinutes = idleTimeoutMinutes
        self.showSeconds = showSeconds
        self.theme = theme
        self.timeFormat = timeFormat
        self.displayMode = displayMode
        self.invoiceIssuerName = invoiceIssuerName
        self.invoiceIssuerDetails = invoiceIssuerDetails
        self.createdAt = .now
        self.updatedAt = .now
    }
}
