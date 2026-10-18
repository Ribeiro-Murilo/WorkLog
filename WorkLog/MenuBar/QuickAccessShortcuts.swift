import Foundation

/// Os dois acessos rápidos mantêm os mesmos atalhos, independentemente da aparência.
@MainActor
enum QuickAccessShortcuts {
    static func register(dependencies: DependencyContainer, toggleDashboard: @escaping @MainActor () -> Void) {
        try? dependencies.shortcutsService.registerDefaultsIfNeeded()
        try? dependencies.shortcutsService.register(action: .startTimer) {
            Task { @MainActor in try? dependencies.timerService.resume() }
        }
        try? dependencies.shortcutsService.register(action: .pauseTimer) {
            Task { @MainActor in try? dependencies.timerService.pause() }
        }
        for action: ShortcutAction in [.openDashboard, .openPopover, .newProject, .searchProject] {
            try? dependencies.shortcutsService.register(action: action) {
                Task { @MainActor in toggleDashboard() }
            }
        }
    }
}
