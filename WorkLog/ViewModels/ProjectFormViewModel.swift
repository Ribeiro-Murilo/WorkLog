import Foundation
import Observation

@MainActor
@Observable
final class ProjectFormViewModel {
    var name: String = ""
    var client: String = ""
    var dailyRateText: String = ""
    var category: ProjectCategory = .work
    var tagsText: String = ""
    var descriptionText: String = ""
    var status: ProjectStatus = .active
    var errorMessage: String?

    private(set) var editingProject: Project?

    private let repository: ProjectRepositoryProtocol
    private let validationService: ValidationServiceProtocol

    var isEditing: Bool { editingProject != nil }

    var tags: [String] {
        tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    init(
        repository: ProjectRepositoryProtocol,
        validationService: ValidationServiceProtocol = ValidationService(),
        editing project: Project? = nil
    ) {
        self.repository = repository
        self.validationService = validationService
        if let project {
            populate(from: project)
        }
    }

    func populate(from project: Project) {
        editingProject = project
        name = project.name
        client = project.client
        dailyRateText = "\(project.dailyRate)"
        category = project.category
        tagsText = project.tags.joined(separator: ", ")
        descriptionText = project.descriptionText
        status = project.status
    }

    @discardableResult
    func save() -> Bool {
        let normalizedRateText = dailyRateText.replacingOccurrences(of: ",", with: ".")
        let rate = Decimal(string: normalizedRateText) ?? 0

        do {
            try validationService.validateProjectFields(name: name, client: client, dailyRate: rate)

            let isDuplicate = try repository.isDuplicate(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                client: client.trimmingCharacters(in: .whitespacesAndNewlines),
                excluding: editingProject?.id
            )
            guard !isDuplicate else { throw ValidationError.duplicateProject }

            if let project = editingProject {
                project.name = name
                project.client = client
                project.dailyRate = rate
                project.category = category
                project.tags = tags
                project.descriptionText = descriptionText
                project.status = status
                try repository.update(project)
            } else {
                let project = Project(
                    name: name,
                    client: client,
                    dailyRate: rate,
                    category: category,
                    tags: tags,
                    descriptionText: descriptionText,
                    status: status
                )
                try repository.insert(project)
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
