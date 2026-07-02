import SwiftUI
import AppKit

/// Fundo translúcido (vibrancy) usado no notch expandido/colapsado, para não ficar
/// preto chapado — deixa passar um blur do conteúdo por trás, como os materiais nativos do macOS.
struct NotchVisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}
