import Foundation

@MainActor
final class NotchScreenRecovery {
    private let isScreenAvailable: @MainActor () -> Bool
    private let onRecovery: @MainActor () -> Void
    private var task: Task<Void, Never>?

    var isMonitoring: Bool { task != nil }

    init(
        isScreenAvailable: @escaping @MainActor () -> Bool,
        onRecovery: @escaping @MainActor () -> Void
    ) {
        self.isScreenAvailable = isScreenAvailable
        self.onRecovery = onRecovery
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.checkAvailability()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func checkAvailability() {
        guard isMonitoring, isScreenAvailable() else { return }
        stop()
        onRecovery()
    }

    isolated deinit {
        task?.cancel()
    }
}
