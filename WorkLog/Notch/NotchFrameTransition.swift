/// Coordena callbacks de animação sem armazenar um frame que possa ficar obsoleto.
struct NotchFrameTransition {
    private(set) var isAnimating = false
    private var generation = 0

    mutating func begin() -> Int {
        generation += 1
        isAnimating = true
        return generation
    }

    mutating func invalidate() {
        generation += 1
        isAnimating = false
    }

    /// Indica se o controlador pode reaplicar a geometria atual do painel.
    mutating func finish(_ completedGeneration: Int) -> Bool {
        if generation == completedGeneration {
            isAnimating = false
        }
        return !isAnimating
    }
}
