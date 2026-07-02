import SwiftUI

struct ProjectRowView: View {
    let project: Project
    var isActive: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: project.category.symbolName)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(project.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                Text(project.client)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isActive {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                    .foregroundStyle(.green)
            }
            if project.isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.yellow)
            }
        }
        .contentShape(Rectangle())
    }
}
