import AppKit
import SwiftUI

/// View interna que apenas hospeda o conteúdo SwiftUI. A detecção de hover NÃO usa
/// `NSTrackingArea` desta view: como o painel muda de tamanho ao expandir, o
/// enter/exit do tracking dispararia em loop (flicker) sempre que o frame animado
/// deixasse o cursor momentaneamente de fora. A expansão é decidida por geometria
/// estável em `NotchWindowController.evaluateHover()`.
private final class NotchHoverView: NSView {}

@MainActor
final class NotchWindowController: NSObject {
    private(set) var isExpanded = false

    /// Tamanho da área expandida, ancorada no topo-centro do notch.
    var expandedSize = CGSize(width: 340, height: 420)

    /// Largura extra desenhada à direita do notch quando colapsado (0 = só o recorte).
    /// Usada para acomodar o timer ao lado do notch. Ao mudar, reposiciona o painel
    /// caso ele esteja colapsado no momento.
    var collapsedTrailingWidth: CGFloat = 0 {
        didSet {
            guard oldValue != collapsedTrailingWidth, !isExpanded else { return }
            applyCollapsedFrame(animated: true)
        }
    }

    /// Conteúdo SwiftUI hospedado no painel. Recebe `isExpanded` e a largura física do
    /// notch a cada mudança de estado.
    var content: ((Bool, CGFloat) -> AnyView)? {
        didSet { refreshContent() }
    }

    private let panel: NSPanel
    private let hoverView: NotchHoverView
    private var hostingView: NSHostingView<AnyView>?
    private weak var currentScreen: NSScreen?
    /// Largura do recorte físico do notch da tela atual (independente da extensão).
    private var physicalNotchWidth: CGFloat = 0
    /// Poll de hover baseado na posição do mouse vs. zonas fixas (evita flicker).
    private var hoverPollTask: Task<Void, Never>?

    override init() {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.hidesOnDeactivate = false

        let hoverView = NotchHoverView(frame: .zero)
        panel.contentView = hoverView

        self.panel = panel
        self.hoverView = hoverView

        super.init()
    }

    func present(on screen: NSScreen) {
        guard let notchFrame = NotchGeometry.notchFrame(on: screen) else { return }

        currentScreen = screen
        physicalNotchWidth = notchFrame.width
        isExpanded = false

        let frame = collapsedFrame(on: screen) ?? notchFrame
        panel.setFrame(frame, display: false)
        hoverView.frame = NSRect(origin: .zero, size: frame.size)
        layoutHostingView()
        refreshContent()

        panel.orderFrontRegardless()
        startHoverPolling()
    }

    func dismiss() {
        hoverPollTask?.cancel()
        hoverPollTask = nil
        panel.orderOut(nil)
    }

    private func startHoverPolling() {
        hoverPollTask?.cancel()
        hoverPollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.evaluateHover()
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
    }

    /// Decide expandir/colapsar comparando a posição do mouse com zonas fixas em
    /// coordenadas de tela. A histerese (enquanto expandido, o cursor pode estar na
    /// zona expandida OU na colapsada) mantém o badge do timer sempre dentro da área
    /// ativa, eliminando o loop de abre/fecha.
    private func evaluateHover() {
        guard let screen = currentScreen,
              let collapsed = collapsedFrame(on: screen),
              let expanded = expandedFrame(on: screen) else { return }

        let mouse = NSEvent.mouseLocation
        let shouldExpand: Bool
        if isExpanded {
            shouldExpand = expanded.contains(mouse) || collapsed.contains(mouse)
        } else {
            shouldExpand = collapsed.contains(mouse)
        }

        if shouldExpand != isExpanded {
            setExpanded(shouldExpand)
        }
    }

    private func setExpanded(_ expanded: Bool) {
        guard isExpanded != expanded, let screen = currentScreen else { return }

        isExpanded = expanded

        let targetFrame = expanded
            ? (expandedFrame(on: screen) ?? panel.frame)
            : (collapsedFrame(on: screen) ?? panel.frame)

        refreshContent()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(targetFrame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.hoverView.frame = NSRect(origin: .zero, size: targetFrame.size)
                self?.layoutHostingView()
            }
        }
    }

    private func layoutHostingView() {
        hostingView?.frame = hoverView.bounds
        hostingView?.autoresizingMask = [.width, .height]
    }

    /// Frame do painel colapsado: começa no recorte do notch e se estende para a
    /// direita por `collapsedTrailingWidth`, sem ultrapassar a borda da tela.
    private func collapsedFrame(on screen: NSScreen) -> NSRect? {
        guard let notchFrame = NotchGeometry.notchFrame(on: screen) else { return nil }
        let maxWidth = screen.frame.maxX - notchFrame.minX
        let width = min(notchFrame.width + max(0, collapsedTrailingWidth), maxWidth)
        return NSRect(x: notchFrame.minX, y: notchFrame.minY, width: width, height: notchFrame.height)
    }

    /// Frame do painel expandido: `expandedSize` ancorado no topo-centro do notch.
    private func expandedFrame(on screen: NSScreen) -> NSRect? {
        guard let notchFrame = NotchGeometry.notchFrame(on: screen) else { return nil }
        return NSRect(
            x: notchFrame.midX - expandedSize.width / 2,
            y: notchFrame.maxY - expandedSize.height,
            width: expandedSize.width,
            height: expandedSize.height
        )
    }

    private func applyCollapsedFrame(animated: Bool) {
        guard !isExpanded, let screen = currentScreen,
              let frame = collapsedFrame(on: screen) else { return }

        refreshContent()

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            } completionHandler: { [weak self] in
                Task { @MainActor in
                    self?.hoverView.frame = NSRect(origin: .zero, size: frame.size)
                    self?.layoutHostingView()
                }
            }
        } else {
            panel.setFrame(frame, display: true)
            hoverView.frame = NSRect(origin: .zero, size: frame.size)
            layoutHostingView()
        }
    }

    private func refreshContent() {
        guard let content else { return }

        let rootView = content(isExpanded, physicalNotchWidth)

        if let hostingView {
            hostingView.rootView = rootView
        } else {
            let hostingView = NSHostingView(rootView: rootView)
            hostingView.frame = hoverView.bounds
            hostingView.autoresizingMask = [.width, .height]
            hoverView.addSubview(hostingView)
            self.hostingView = hostingView
        }
    }
}
