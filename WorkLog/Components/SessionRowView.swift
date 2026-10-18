import SwiftUI

struct SessionRowView: View {
    let session: Session
    var onEditCycles: (() -> Void)? = nil

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                SessionCycleDetailsView(periods: session.workPeriods)
                if let onEditCycles, session.status != .running {
                    Button("Editar ciclos", action: onEditCycles)
                        .buttonStyle(.bordered)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 4)
        } label: {
            summary
        }
        .padding(.vertical, 4)
    }

    private var summary: some View {
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
    }
}

/// A mesma leitura de ciclos é usada na lista e no formulário bloqueado.
struct SessionCycleDetailsView: View {
    let periods: [SessionWorkPeriod]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(periods.enumerated()), id: \.offset) { index, period in
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ciclo \(index + 1)").font(.subheadline).fontWeight(.medium)
                    LabeledContent("Início") { timestamp(period.start) }
                    LabeledContent("Fim") {
                        if let end = period.end {
                            timestamp(end)
                        } else {
                            Text("Em andamento").foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Duração") {
                        if let end = period.end {
                            duration(from: period.start, to: end)
                        } else {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                duration(from: period.start, to: context.date)
                            }
                        }
                    }
                }
                .font(.callout)
                if index < periods.count - 1 { Divider() }
            }
        }
    }

    private func timestamp(_ date: Date) -> some View {
        Text(date, format: .dateTime.day().month(.twoDigits).year().hour().minute().second())
            .monospacedDigit()
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func duration(from start: Date, to end: Date) -> some View {
        Text(max(0, end.timeIntervalSince(start)).formattedClock(showSeconds: true))
            .monospacedDigit()
    }
}
