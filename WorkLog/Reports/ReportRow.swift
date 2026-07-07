import Foundation

/// Representa uma linha do relatório, seja uma sessão individual (modo detalhado)
/// ou um grupo consolidado de sessões (modo resumido por projeto e dia).
struct ReportRow: Identifiable {
    let id: String
    let projectName: String
    let client: String
    let date: Date
    let startTime: Date
    let endTime: Date?
    let durationSeconds: TimeInterval
    let category: ProjectCategory
    let status: SessionStatus
    let estimatedValue: Decimal
    let note: String
    let tags: [String]
    let descriptionText: String
    let sessionCount: Int

    init(session: Session) {
        self.id = session.id.uuidString
        self.projectName = session.project?.name ?? "—"
        self.client = session.project?.client ?? "—"
        self.date = session.date
        self.startTime = session.startTime
        self.endTime = session.endTime
        self.durationSeconds = session.durationSeconds
        self.category = session.category
        self.status = session.status
        self.estimatedValue = session.estimatedValue
        self.note = session.note
        self.tags = session.project?.tags ?? []
        self.descriptionText = session.project?.descriptionText ?? ""
        self.sessionCount = 1
    }

    init(
        id: String,
        projectName: String,
        client: String,
        date: Date,
        startTime: Date,
        endTime: Date?,
        durationSeconds: TimeInterval,
        category: ProjectCategory,
        status: SessionStatus,
        estimatedValue: Decimal,
        note: String,
        tags: [String],
        descriptionText: String,
        sessionCount: Int
    ) {
        self.id = id
        self.projectName = projectName
        self.client = client
        self.date = date
        self.startTime = startTime
        self.endTime = endTime
        self.durationSeconds = durationSeconds
        self.category = category
        self.status = status
        self.estimatedValue = estimatedValue
        self.note = note
        self.tags = tags
        self.descriptionText = descriptionText
        self.sessionCount = sessionCount
    }
}
