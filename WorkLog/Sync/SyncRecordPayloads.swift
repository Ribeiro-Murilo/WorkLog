import Foundation

/// Numeric reference-date timestamps retain subsecond precision and produce stable bytes.
enum SyncPayloadCodec {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }
}

struct BillingSettingsSyncPayload: Codable {
    var invoiceIssuerName: String
    var invoiceIssuerDetails: String
}

struct ProjectSyncPayload: Codable {
    var id: UUID
    var name: String
    var client: String
    var dailyRate: Decimal
    var category: ProjectCategory
    var tags: [String]
    var descriptionText: String
    var status: ProjectStatus
    var isArchived: Bool
    var isFavorite: Bool
    var createdAt: Date
    var updatedAt: Date

    init(_ model: Project) {
        id = model.id
        name = model.name
        client = model.client
        dailyRate = model.dailyRate
        category = model.category
        tags = model.tags
        descriptionText = model.descriptionText
        status = model.status
        isArchived = model.isArchived
        isFavorite = model.isFavorite
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    @MainActor func materialize(existing: Project?) -> Project {
        let model = existing ?? Project(name: name, client: client, dailyRate: dailyRate, category: category)
        model.id = id
        model.name = name
        model.client = client
        model.dailyRate = dailyRate
        model.category = category
        model.tags = tags
        model.descriptionText = descriptionText
        model.status = status
        model.isArchived = isArchived
        model.isFavorite = isFavorite
        model.createdAt = createdAt
        model.updatedAt = updatedAt
        return model
    }
}

struct SessionSyncPayload: Codable {
    var id: UUID
    var projectId: UUID?
    var date: Date
    var startTime: Date
    var endTime: Date?
    var durationSeconds: TimeInterval
    var note: String
    var category: ProjectCategory
    var status: SessionStatus
    var createdAt: Date
    var updatedAt: Date

    init(_ model: Session) {
        id = model.id
        projectId = model.project?.id
        date = model.date
        startTime = model.startTime
        endTime = model.endTime
        durationSeconds = model.durationSeconds
        note = model.note
        category = model.category
        status = model.status
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    @MainActor func materialize(existing: Session?, project: Project?) -> Session {
        let model = existing ?? Session(project: project, date: date, startTime: startTime, category: category, status: status)
        model.id = id
        model.project = project
        model.date = date
        model.startTime = startTime
        model.endTime = endTime
        model.durationSeconds = durationSeconds
        model.note = note
        model.category = category
        model.status = status
        model.createdAt = createdAt
        model.updatedAt = updatedAt
        return model
    }
}

struct CommentSyncPayload: Codable {
    var id: UUID
    var text: String
    var author: String
    var createdAt: Date
    var projectId: UUID?

    init(_ model: Comment) {
        id = model.id
        text = model.text
        author = model.author
        createdAt = model.createdAt
        projectId = model.project?.id
    }

    @MainActor func materialize(existing: Comment?, project: Project?) -> Comment {
        let model = existing ?? Comment(text: text, author: author, project: project)
        model.id = id
        model.text = text
        model.author = author
        model.createdAt = createdAt
        model.project = project
        return model
    }
}

struct ReportPresetSyncPayload: Codable {
    var id: UUID
    var name: String
    var columnsRaw: [String]
    var groupingRaw: String
    var createdAt: Date
    var updatedAt: Date

    init(_ model: ReportPreset) {
        id = model.id
        name = model.name
        columnsRaw = model.columnsRaw
        groupingRaw = model.groupingRaw
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    @MainActor func materialize(existing: ReportPreset?) -> ReportPreset {
        let model = existing ?? ReportPreset(name: name, columns: [], grouping: .detailed)
        model.id = id
        model.name = name
        model.columnsRaw = columnsRaw
        model.groupingRaw = groupingRaw
        model.createdAt = createdAt
        model.updatedAt = updatedAt
        return model
    }
}

struct InvoiceSyncPayload: Codable {
    var id: UUID
    var number: Int
    var client: String
    var issueDate: Date
    var periodStart: Date
    var periodEnd: Date
    var lineItems: [InvoiceLineItem]
    var totalValue: Decimal
    var status: InvoiceStatus
    var notes: String
    var createdAt: Date
    var updatedAt: Date

    init(_ model: Invoice) {
        id = model.id
        number = model.number
        client = model.client
        issueDate = model.issueDate
        periodStart = model.periodStart
        periodEnd = model.periodEnd
        lineItems = model.lineItems
        totalValue = model.totalValue
        status = model.status
        notes = model.notes
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    @MainActor func materialize(existing: Invoice?) -> Invoice {
        let model = existing ?? Invoice(number: number, client: client, issueDate: issueDate, periodStart: periodStart, periodEnd: periodEnd, lineItems: lineItems)
        model.id = id
        model.number = number
        model.client = client
        model.issueDate = issueDate
        model.periodStart = periodStart
        model.periodEnd = periodEnd
        model.lineItems = lineItems
        model.totalValue = totalValue
        model.status = status
        model.notes = notes
        model.createdAt = createdAt
        model.updatedAt = updatedAt
        return model
    }
}

struct AppSettingsSyncPayload: Codable {
    var id: UUID
    var launchAtLogin: Bool
    var idleTimeoutMinutes: Int
    var showSeconds: Bool
    var theme: AppTheme
    var timeFormat: TimeFormatPreference
    var displayMode: AppDisplayMode
    var lastBackupDate: Date?
    var invoiceIssuerName: String
    var invoiceIssuerDetails: String
    var lastInvoiceNumber: Int
    var includeLogoInPDF: Bool
    var createdAt: Date
    var updatedAt: Date

    init(_ model: AppSettings) {
        id = model.id
        launchAtLogin = model.launchAtLogin
        idleTimeoutMinutes = model.idleTimeoutMinutes
        showSeconds = model.showSeconds
        theme = model.theme
        timeFormat = model.timeFormat
        displayMode = model.displayMode
        lastBackupDate = model.lastBackupDate
        invoiceIssuerName = model.invoiceIssuerName
        invoiceIssuerDetails = model.invoiceIssuerDetails
        lastInvoiceNumber = model.lastInvoiceNumber
        includeLogoInPDF = model.includeLogoInPDF
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    @MainActor func materialize(existing: AppSettings?) -> AppSettings {
        let model = existing ?? AppSettings()
        model.id = id
        model.launchAtLogin = launchAtLogin
        model.idleTimeoutMinutes = idleTimeoutMinutes
        model.showSeconds = showSeconds
        model.theme = theme
        model.timeFormat = timeFormat
        model.displayMode = displayMode
        model.lastBackupDate = lastBackupDate
        model.invoiceIssuerName = invoiceIssuerName
        model.invoiceIssuerDetails = invoiceIssuerDetails
        model.lastInvoiceNumber = max(model.lastInvoiceNumber, lastInvoiceNumber)
        model.includeLogoInPDF = includeLogoInPDF
        model.createdAt = createdAt
        model.updatedAt = updatedAt
        return model
    }
}

struct ShortcutBindingSyncPayload: Codable {
    var actionRawValue: String
    var keyCode: UInt32
    var modifiers: UInt32
    var isEnabled: Bool
    var updatedAt: Date

    init(_ model: ShortcutBinding) {
        actionRawValue = model.actionRawValue
        keyCode = model.keyCode
        modifiers = model.modifiers
        isEnabled = model.isEnabled
        updatedAt = model.updatedAt
    }

    @MainActor func materialize(existing: ShortcutBinding?) -> ShortcutBinding {
        let model = existing ?? ShortcutBinding(action: ShortcutAction(rawValue: actionRawValue) ?? .startTimer, keyCombo: KeyCombo(keyCode: keyCode, modifiers: modifiers))
        model.actionRawValue = actionRawValue
        model.keyCode = keyCode
        model.modifiers = modifiers
        model.isEnabled = isEnabled
        model.updatedAt = updatedAt
        return model
    }
}
