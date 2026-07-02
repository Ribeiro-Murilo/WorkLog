import AppKit
import SwiftUI

/// View interna que hospeda o conteúdo SwiftUI e detecta hover via `NSTrackingArea`,
/// já que o painel não se torna key apenas por causa do mouse.
private final class NotchHoverView: NSView {
    var onHoverChanged: ((Bool) -> Void)?

    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }
}

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

        hoverView.onHoverChanged = { [weak self] hovering in
            self?.setExpanded(hovering)
        }
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
    }

    func dismiss() {
        panel.orderOut(nil)
    }

    private func setExpanded(_ expanded: Bool) {
        guard isExpanded != expanded, let screen = currentScreen,
              let notchFrame = NotchGeometry.notchFrame(on: screen) else { return }

        isExpanded = expanded

        let targetFrame: NSRect
        if expanded {
            let centerX = notchFrame.midX
            targetFrame = NSRect(
                x: centerX - expandedSize.width / 2,
                y: notchFrame.maxY - expandedSize.height,
                width: expandedSize.width,
                height: expandedSize.height
            )
        } else {
            targetFrame = collapsedFrame(on: screen) ?? notchFrame
        }

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
