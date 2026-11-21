import SwiftUI

struct ProjectMoneyCard: View {
    @Environment(PTAXService.self) private var ptax

    let title: String
    let symbolName: String
    let amount: Decimal
    let currency: ProjectCurrency
    let displayCurrency: ProjectCurrency
    var selection: Binding<ProjectCurrency>?
    let fillsRowHeight: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Label(title, systemImage: symbolName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let selection {
                    Spacer(minLength: 4)
                    Menu {
                        Picker("Moeda em destaque", selection: selection) {
                            ForEach(ProjectCurrency.allCases, id: \.self) { currency in
                                Text(currency.rawValue).tag(currency)
                            }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Text(displayCurrency.rawValue)
                            .font(.caption.weight(.medium))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.visible)
                    .controlSize(.small)
                    .fixedSize()
                    .accessibilityLabel("Moeda em destaque")
                    .accessibilityValue(displayCurrency.rawValue)
                    .help("Moeda em destaque")
                }
            }
            .frame(minHeight: 20)

            Text(formattedAmount(in: displayCurrency))
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(ProjectCurrency.allCases.filter { $0 != displayCurrency }, id: \.self) { currency in
                    Text(formattedAmount(in: currency))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .monospacedDigit()
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: fillsRowHeight ? .infinity : nil, alignment: .topLeading)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
    }

    private func formattedAmount(in target: ProjectCurrency) -> String {
        guard let value = ptax.convert(amount, from: currency, to: target) else {
            return "\(target.rawValue) —"
        }
        let formatted = value.formatted(currency: target)
        return currency == target || amount == 0 ? formatted : "≈ \(formatted)"
    }
}
