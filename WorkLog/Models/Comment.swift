import Foundation
import SwiftData

@Model
final class Comment {
    var id: UUID = UUID()
    var text: String = ""
    var author: String = ""
    var createdAt: Date = Date.now
    var project: Project?

    init(text: String, author: String, project: Project?) {
        self.id = UUID()
        self.text = text
        self.author = author
        self.project = project
        self.createdAt = .now
    }
}
