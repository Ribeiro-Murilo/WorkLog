import AppKit

enum NotchGeometry {
    static func hasNotch(on screen: NSScreen) -> Bool {
        screen.safeAreaInsets.top > 0
    }

    static func notchFrame(on screen: NSScreen) -> CGRect? {
        guard hasNotch(on: screen) else { return nil }

        let leftWidth = screen.auxiliaryTopLeftArea?.width ?? 0
        let rightWidth = screen.auxiliaryTopRightArea?.width ?? 0
        let notchHeight = screen.safeAreaInsets.top
        let notchWidth = screen.frame.width - leftWidth - rightWidth
        let notchX = screen.frame.minX + leftWidth
        let notchY = screen.frame.maxY - notchHeight

        return CGRect(x: notchX, y: notchY, width: notchWidth, height: notchHeight)
    }

    static var hasAnyNotch: Bool {
        NSScreen.screens.contains { hasNotch(on: $0) }
    }

    static var primaryNotchScreen: NSScreen? {
        if let main = NSScreen.main, hasNotch(on: main) {
            return main
        }
        return NSScreen.screens.first { hasNotch(on: $0) }
    }
}
