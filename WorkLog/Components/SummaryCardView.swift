import SwiftUI

struct SummaryCardView: View {
    let title: String
    let value: String
    var symbolName: String?
    var fillsRowHeight = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let symbolName {
                    Image(systemName: symbolName)
                        .foregroundStyle(.secondary)
                }
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: fillsRowHeight ? 20 : nil)
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: fillsRowHeight ? .infinity : nil, alignment: .topLeading)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
    }
}
