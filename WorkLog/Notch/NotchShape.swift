import SwiftUI

struct NotchShape: Shape {
    var cornerRadius: CGFloat = 12
    /// Espaço incluído na janela para as curvas côncavas junto à borda da tela.
    /// Zero preserva a geometria do recorte físico no estado colapsado.
    var shoulderRadius: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        guard rect.width > 0, rect.height > 0 else { return Path() }
        let shoulder = min(max(0, shoulderRadius), rect.width / 4, rect.height / 2)
        let radius = min(max(0, cornerRadius), (rect.width - 2 * shoulder) / 2,
                         (rect.height - shoulder) / 2)
        let left = rect.minX + shoulder
        let right = rect.maxX - shoulder
        let k: CGFloat = 0.5522847498 // aproximação cúbica de um quarto de círculo
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addCurve(to: CGPoint(x: right, y: rect.minY + shoulder),
                      control1: CGPoint(x: rect.maxX - shoulder * k, y: rect.minY),
                      control2: CGPoint(x: right, y: rect.minY + shoulder * (1 - k)))
        path.addLine(to: CGPoint(x: right, y: rect.maxY - radius))
        path.addCurve(to: CGPoint(x: right - radius, y: rect.maxY),
                      control1: CGPoint(x: right, y: rect.maxY - radius * (1 - k)),
                      control2: CGPoint(x: right - radius * (1 - k), y: rect.maxY))
        path.addLine(to: CGPoint(x: left + radius, y: rect.maxY))
        path.addCurve(to: CGPoint(x: left, y: rect.maxY - radius),
                      control1: CGPoint(x: left + radius * (1 - k), y: rect.maxY),
                      control2: CGPoint(x: left, y: rect.maxY - radius * (1 - k)))
        path.addLine(to: CGPoint(x: left, y: rect.minY + shoulder))
        path.addCurve(to: CGPoint(x: rect.minX, y: rect.minY),
                      control1: CGPoint(x: left, y: rect.minY + shoulder * (1 - k)),
                      control2: CGPoint(x: rect.minX + shoulder * k, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

enum NotchPanelMetrics {
    static let contentWidth: CGFloat = 340
    static let shoulderRadius: CGFloat = 14
    static let bottomRadius: CGFloat = 20
    static let expandedWidth = contentWidth + 2 * shoulderRadius
}
