/// Resolve a tela atual pelo identificador, sem depender da vida útil de NSScreen.
@MainActor
final class NotchScreenResolver<Screen: AnyObject> {
    private(set) var selectedDisplayID: UInt32?
    private let screens: () -> [Screen]
    private let identifier: (Screen) -> UInt32?
    private let hasNotch: (Screen) -> Bool

    init(
        screens: @escaping () -> [Screen],
        identifier: @escaping (Screen) -> UInt32?,
        hasNotch: @escaping (Screen) -> Bool
    ) {
        self.screens = screens
        self.identifier = identifier
        self.hasNotch = hasNotch
    }

    func select(_ screen: Screen) {
        selectedDisplayID = identifier(screen)
    }

    func resolve() -> Screen? {
        let available = screens().filter(hasNotch)
        if let selectedDisplayID,
           let selected = available.first(where: { identifier($0) == selectedDisplayID }) {
            return selected
        }

        guard let fallback = available.first else { return nil }
        selectedDisplayID = identifier(fallback)
        return fallback
    }

    func reset() {
        selectedDisplayID = nil
    }
}
