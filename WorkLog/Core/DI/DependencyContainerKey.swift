import SwiftUI

private struct DependencyContainerKey: EnvironmentKey {
    @MainActor static var defaultValue: DependencyContainer = .live()
}

extension EnvironmentValues {
    var dependencies: DependencyContainer {
        get { self[DependencyContainerKey.self] }
        set { self[DependencyContainerKey.self] = newValue }
    }
}
