import Foundation

extension Decimal {
    func formatted(currency: ProjectCurrency, showCode: Bool = false) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.rawValue
        if showCode {
            formatter.currencySymbol = currency.rawValue
        }
        return formatter.string(from: self as NSDecimalNumber) ?? "\(currency.rawValue) \(self)"
    }
}
