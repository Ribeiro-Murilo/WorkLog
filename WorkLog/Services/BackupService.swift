import Foundation

private struct ProjectBackupDTO: Codable {
    let id: UUID
    let name: String
    let client: String
    let dailyRate: Decimal
    let category: ProjectCategory
    let tags: [String]
    let descriptionText: String
    let status: ProjectStatus
    let isArchived: Bool
    let isFavorite: Bool

    init(from project: Project) {
        id = project.id
        name = project.name
        client = project.client
        dailyRate = project.dailyRate
        category = project.category
        tags = project.tags
        descriptionText = project.descriptionText
        status = project.status
        isArchived = project.isArchived
        isFavorite = project.isFavorite
    }
}

private struct SessionBackupDTO: Codable {
    let id: UUID
    let projectId: UUID?
    let date: Date
    let startTime: Date
    let endTime: Date?
    let durationSeconds: TimeInterval
    let note: String
    let category: ProjectCategory
    let status: SessionStatus

    init(from session: Session) {
        id = session.id
        projectId = session.project?.id
        date = session.date
        startTime = session.startTime
        endTime = session.endTime
        durationSeconds = session.durationSeconds
        note = session.note
        category = session.category
        status = session.status
    }
}

private struct BackupPayload: Codable {
    let exportedAt: Date
    let projects: [ProjectBackupDTO]
    let sessions: [SessionBackupDTO]
}

@MainActor
protocol BackupServiceProtocol {
    func exportBackup(to url: URL) throws
    func importBackup(from url: URL) throws
}

@MainActor
final class BackupService: BackupServiceProtocol {
    private let projectRepository: ProjectRepositoryProtocol
    private let sessionRepository: SessionRepositoryProtocol

    init(projectRepository: ProjectRepositoryProtocol, sessionRepository: SessionRepositoryProtocol) {
        self.projectRepository = projectRepository
        self.sessionRepository = sessionRepository
    }

    func exportBackup(to url: URL) throws {
        let projects = try projectRepository.fetchAll(includeArchived: true)
        let sessions = try sessionRepository.fetchAll(for: nil)

        let payload = BackupPayload(
            exportedAt: .now,
            projects: projects.map(ProjectBackupDTO.init),
            sessions: sessions.map(SessionBackupDTO.init)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        try data.write(to: url, options: .atomic)
    }

    func importBackup(from url: URL) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: url)
        let payload = try decoder.decode(BackupPayload.self, from: data)

        var restoredProjectsById: [UUID: Project] = [:]
        for dto in payload.projects {
            let project = Project(
                name: dto.name,
                client: dto.client,
                dailyRate: dto.dailyRate,
                category: dto.category,
                tags: dto.tags,
                descriptionText: dto.descriptionText,
                status: dto.status,
                isArchived: dto.isArchived,
                isFavorite: dto.isFavorite
            )
            try projectRepository.insert(project)
            restoredProjectsById[dto.id] = project
        }

        for dto in payload.sessions {
            let session = Session(
                project: dto.projectId.flatMap { restoredProjectsById[$0] },
                date: dto.date,
                startTime: dto.startTime,
                endTime: dto.endTime,
                durationSeconds: dto.durationSeconds,
                note: dto.note,
                category: dto.category,
                status: dto.status
            )
            try sessionRepository.insert(session)
        }
    }
}
