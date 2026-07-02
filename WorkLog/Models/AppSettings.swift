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
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(
        launchAtLogin: Bool = true,
        idleTimeoutMinutes: Int = 10,
        showSeconds: Bool = true,
        theme: AppTheme = .system,
        timeFormat: TimeFormatPreference = .twentyFourHour,
        displayMode: AppDisplayMode = .menuBar
    ) {
        self.id = UUID()
        self.launchAtLogin = launchAtLogin
        self.idleTimeoutMinutes = idleTimeoutMinutes
        self.showSeconds = showSeconds
        self.theme = theme
        self.timeFormat = timeFormat
        self.displayMode = displayMode
        self.createdAt = .now
        self.updatedAt = .now
    }
}
