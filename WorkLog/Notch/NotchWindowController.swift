import AppKit
import OSLog
import SwiftUI

/// View interna que apenas hospeda o conteúdo SwiftUI. A detecção de hover NÃO usa
/// `NSTrackingArea` desta view: como o painel muda de tamanho ao expandir, o
/// enter/exit do tracking dispararia em loop (flicker) sempre que o frame animado
/// deixasse o cursor momentaneamente de fora. A expansão é decidida por geometria
/// estável em `NotchWindowController.evaluateHover()`.
private final class NotchHoverView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// O primeiro clique precisa atravessar mesmo quando outro app ainda possui a janela
/// key. Sem isso, o clique usado para reativar o painel pode ser apenas consumido pelo
/// AppKit, sem chegar ao `Button` SwiftUI.
private final class NotchHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Painel borderless que ainda pode virar *key window*. Sem isto, `canBecomeKey`
/// retorna `false` (padrão para janelas borderless) e os controles SwiftUI dentro
/// do notch expandido não recebem cliques. `.nonactivatingPanel` continua evitando
/// que a app inteira seja ativada ao interagir.
private final class NotchPanel: NSPanel {
    var onMouseEvent: ((NSEvent, NSView?) -> Void)?

    override var canBecomeKey: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp:
            onMouseEvent?(event, contentView?.hitTest(event.locationInWindow))
        default:
            break
        }
        super.sendEvent(event)
    }
}

@MainActor
final class NotchWindowController: NSObject, NSWindowDelegate {
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

    /// Conteúdo SwiftUI hospedado no painel. Recebe `isExpanded`, a largura física do
    /// notch e a altura física do notch a cada mudança de estado.
    var content: ((Bool, CGFloat, CGFloat) -> AnyView)? {
        didSet { refreshContent() }
    }

    private let panel: NSPanel
    private let hoverView: NotchHoverView
    private var hostingView: NSHostingView<AnyView>?
    private weak var currentScreen: NSScreen?
    /// Largura do recorte físico do notch da tela atual (independente da extensão).
    private var physicalNotchWidth: CGFloat = 0
    /// Altura do recorte físico do notch (usada para não desenhar conteúdo importante
    /// atrás da câmera, já que o painel expandido é ancorado no topo físico da tela).
    private var physicalNotchHeight: CGFloat = 0
    /// Poll de hover baseado na posição do mouse vs. zonas fixas (evita flicker).
    private var hoverPollTask: Task<Void, Never>?
    /// O macOS pode retirar a key window de um painel não-ativante mesmo enquanto
    /// o cursor continua sobre o notch expandido. Evita uma sequência de chamadas
    /// de foco a cada ciclo do poll, que pode causar flicker.
    private var lastKeyRecoveryAt = Date.distantPast
    private let logger = Logger(subsystem: "RibeiroWorkes.WorkLog", category: "NotchInteraction")
    private var lastDiagnosticState: String?

    override init() {
        let panel = NotchPanel(
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
        hoverView.autoresizingMask = [.width, .height]
        panel.contentView = hoverView

        self.panel = panel
        self.hoverView = hoverView

        super.init()
        panel.delegate = self
        panel.onMouseEvent = { [weak self] event, hitView in
            self?.logMouseEvent(event, hitView: hitView)
        }
    }

    func present(on screen: NSScreen) {
        guard let notchFrame = NotchGeometry.notchFrame(on: screen) else { return }

        currentScreen = screen
        physicalNotchWidth = notchFrame.width
        physicalNotchHeight = notchFrame.height
        isExpanded = false

        let frame = collapsedFrame(on: screen) ?? notchFrame
        panel.setFrame(frame, display: false)
        hoverView.frame = NSRect(origin: .zero, size: frame.size)
        layoutHostingView()
        refreshContent()

        panel.orderFrontRegardless()
        logger.notice("present screen=\(screen.localizedName, privacy: .public) frame=\(NSStringFromRect(frame), privacy: .public)")
        startHoverPolling()
    }

    func dismiss() {
        hoverPollTask?.cancel()
        hoverPollTask = nil
        lastKeyRecoveryAt = .distantPast
        logger.notice("dismiss expanded=\(self.isExpanded) key=\(self.panel.isKeyWindow)")
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

        logDiagnosticState(
            mouse: mouse,
            screen: screen,
            collapsed: collapsed,
            expanded: expanded,
            shouldExpand: shouldExpand
        )

        if shouldExpand != isExpanded {
            setExpanded(shouldExpand)
        } else if isExpanded && !panel.isKeyWindow {
            recoverKeyWindowIfNeeded()
        }
    }

    /// Recupera a key window somente enquanto o cursor permanece na área expandida.
    /// O intervalo evita disputar foco com o AppKit durante trocas de Space, wake ou
    /// uma animação de abertura.
    private func recoverKeyWindowIfNeeded() {
        guard panel.isVisible else { return }

        let now = Date()
        guard now.timeIntervalSince(lastKeyRecoveryAt) >= 0.25 else { return }
        lastKeyRecoveryAt = now

        logger.notice(
            "recoverKeyWindow expanded=\(self.isExpanded) frame=\(NSStringFromRect(self.panel.frame), privacy: .public)"
        )
        panel.makeKeyAndOrderFront(nil)
    }

    private func setExpanded(_ expanded: Bool) {
        guard isExpanded != expanded, let screen = currentScreen else { return }

        isExpanded = expanded

        let targetFrame = expanded
            ? (expandedFrame(on: screen) ?? panel.frame)
            : (collapsedFrame(on: screen) ?? panel.frame)

        logger.notice(
            "transition expanded=\(expanded) keyBefore=\(self.panel.isKeyWindow) from=\(NSStringFromRect(self.panel.frame), privacy: .public) to=\(NSStringFromRect(targetFrame), privacy: .public)"
        )

        // Torna o painel *key* ao expandir para que os controles SwiftUI recebam
        // cliques; ao colapsar, devolve o foco para não reter a *key window*.
        if expanded {
            lastKeyRecoveryAt = Date()
            panel.makeKeyAndOrderFront(nil)
        } else {
            lastKeyRecoveryAt = .distantPast
            panel.resignKey()
        }

        refreshContent()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(targetFrame, display: true)
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
            }
        } else {
            panel.setFrame(frame, display: true)
            hoverView.frame = NSRect(origin: .zero, size: frame.size)
            layoutHostingView()
        }
    }

    private func refreshContent() {
        guard let content else { return }

        let rootView = content(isExpanded, physicalNotchWidth, physicalNotchHeight)

        if let hostingView {
            hostingView.rootView = rootView
        } else {
            let hostingView = NotchHostingView(rootView: rootView)
            hostingView.frame = hoverView.bounds
            hostingView.autoresizingMask = [.width, .height]
            hoverView.addSubview(hostingView)
            self.hostingView = hostingView
        }
    }

    private func logDiagnosticState(
        mouse: NSPoint,
        screen: NSScreen,
        collapsed: NSRect,
        expanded: NSRect,
        shouldExpand: Bool
    ) {
        let physical = NotchGeometry.notchFrame(on: screen) ?? .zero
        let inPhysicalNotch = physical.contains(mouse)
        let inCollapsed = collapsed.contains(mouse)
        let inExpanded = expanded.contains(mouse)
        let inTimerBadge = inCollapsed && !inPhysicalNotch
        let hostingFrame = hostingView?.frame ?? .zero
        let state = [
            "expanded=\(isExpanded)",
            "shouldExpand=\(shouldExpand)",
            "physical=\(inPhysicalNotch)",
            "badge=\(inTimerBadge)",
            "expandedZone=\(inExpanded)",
            "key=\(panel.isKeyWindow)",
            "main=\(panel.isMainWindow)",
            "visible=\(panel.isVisible)",
            "activeSpace=\(panel.isOnActiveSpace)",
            "appActive=\(NSApp.isActive)",
            "occlusion=\(panel.occlusionState.rawValue)",
            "panel=\(NSStringFromRect(panel.frame))",
            "hover=\(NSStringFromRect(hoverView.frame))",
            "hosting=\(NSStringFromRect(hostingFrame))"
        ].joined(separator: " ")

        guard state != lastDiagnosticState else { return }
        lastDiagnosticState = state
        let topDistance = screen.frame.maxY - mouse.y
        logger.debug(
            "state \(state, privacy: .public) mouse=\(NSStringFromPoint(mouse), privacy: .public) topDistance=\(topDistance)"
        )
    }

    private func logMouseEvent(_ event: NSEvent, hitView: NSView?) {
        let hitViewName = hitView.map { String(describing: type(of: $0)) } ?? "nil"
        logger.notice(
            "mouseEvent type=\(String(describing: event.type), privacy: .public) location=\(NSStringFromPoint(event.locationInWindow), privacy: .public) hit=\(hitViewName, privacy: .public) expanded=\(self.isExpanded) key=\(self.panel.isKeyWindow)"
        )
    }

    func windowDidBecomeKey(_ notification: Notification) {
        logger.notice("windowDidBecomeKey expanded=\(self.isExpanded) frame=\(NSStringFromRect(self.panel.frame), privacy: .public)")
    }

    func windowDidResignKey(_ notification: Notification) {
        logger.notice("windowDidResignKey expanded=\(self.isExpanded) frame=\(NSStringFromRect(self.panel.frame), privacy: .public)")
    }
}
