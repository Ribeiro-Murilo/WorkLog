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

    /// Conteúdo SwiftUI hospedado no painel. Recebe `isExpanded` a cada mudança de estado.
    var content: ((Bool) -> AnyView)? {
        didSet { refreshContent() }
    }

    private let panel: NSPanel
    private let hoverView: NotchHoverView
    private var hostingView: NSHostingView<AnyView>?
    private weak var currentScreen: NSScreen?

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
        isExpanded = false

        panel.setFrame(notchFrame, display: false)
        hoverView.frame = NSRect(origin: .zero, size: notchFrame.size)
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
            targetFrame = notchFrame
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

    private func refreshContent() {
        guard let content else { return }

        let rootView = content(isExpanded)

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
