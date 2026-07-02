import SwiftUI

struct SessionRowView: View {
    let session: Session

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.project?.name ?? "—")
                    .font(.system(size: 13, weight: .medium))
                Text(DateFormatter.shortDate.string(from: session.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(session.durationSeconds.formattedClock(showSeconds: false))
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                Text(session.status.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
