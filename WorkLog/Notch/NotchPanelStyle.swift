import SwiftUI

enum NotchPanelStyle {
    static let secondary = Color(red: 165 / 255, green: 167 / 255, blue: 174 / 255)
    static let divider = Color.white.opacity(0.10)
    static let control = Color.white.opacity(0.065)

    /// UUID bytes produce the same identifier color across launches and sync devices.
    static func projectColor(_ id: UUID) -> Color {
        let palette: [Color] = [
            Color(red: 0.22, green: 0.80, blue: 0.81),
            Color(red: 0.48, green: 0.53, blue: 1.00),
            Color(red: 1.00, green: 0.63, blue: 0.29),
            Color(red: 0.56, green: 0.83, blue: 0.37),
            Color(red: 0.89, green: 0.52, blue: 0.72),
            Color(red: 0.78, green: 0.66, blue: 0.96)
        ]
        let index = id.uuidString.utf8.reduce(0) { ($0 * 31 + Int($1)) % palette.count }
        return palette[index]
    }
}

struct NotchPanelButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(prominent ? Color.black : Color.white)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(prominent ? Color(white: configuration.isPressed ? 0.72 : 0.91) : NotchPanelStyle.control)
            }
            .overlay {
                if !prominent {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.20))
                }
            }
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
