import Testing
@testable import WorkLog

@MainActor
struct NotchFrameTransitionTests {
    @Test func latestCompletionStopsAnimating() {
        var transition = NotchFrameTransition()
        let generation = transition.begin()
        #expect(transition.isAnimating)

        let canApplyCurrentFrame = transition.finish(generation)

        #expect(canApplyCurrentFrame)
        #expect(!transition.isAnimating)
    }

    @Test func invalidatedCompletionCanReapplyCurrentFrame() {
        var transition = NotchFrameTransition()
        let generation = transition.begin()
        transition.invalidate()
        #expect(!transition.isAnimating)

        let canApplyCurrentFrame = transition.finish(generation)

        #expect(canApplyCurrentFrame)
        #expect(!transition.isAnimating)
    }

    @Test func oldCompletionCannotEndNewAnimation() {
        var transition = NotchFrameTransition()
        let oldGeneration = transition.begin()
        let newGeneration = transition.begin()

        let canApplyOldCompletion = transition.finish(oldGeneration)

        #expect(!canApplyOldCompletion)
        #expect(transition.isAnimating)

        let canApplyNewCompletion = transition.finish(newGeneration)

        #expect(canApplyNewCompletion)
        #expect(!transition.isAnimating)
    }

    @Test func oldCompletionAfterNewAnimationCanReapplyCurrentFrame() {
        var transition = NotchFrameTransition()
        let oldGeneration = transition.begin()
        let newGeneration = transition.begin()
        _ = transition.finish(newGeneration)

        let canApplyCurrentFrame = transition.finish(oldGeneration)

        #expect(canApplyCurrentFrame)
        #expect(!transition.isAnimating)
    }
}
