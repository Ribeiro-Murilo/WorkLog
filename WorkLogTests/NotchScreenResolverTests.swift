import Testing
@testable import WorkLog

@MainActor
struct NotchScreenResolverTests {
    private final class Screen {
        let id: UInt32?
        let hasNotch: Bool

        init(_ id: UInt32?, hasNotch: Bool = true) {
            self.id = id
            self.hasNotch = hasNotch
        }
    }

    @MainActor
    private final class Screens {
        var available: [Screen] = []

        func resolver() -> NotchScreenResolver<Screen> {
            NotchScreenResolver(
                screens: { self.available },
                identifier: { $0.id },
                hasNotch: { $0.hasNotch }
            )
        }
    }

    @Test func usesReplacementInstanceOfSelectedDisplay() {
        let source = Screens()
        let original = Screen(1)
        let replacement = Screen(1)
        let other = Screen(2)
        source.available = [original]
        let resolver = source.resolver()
        resolver.select(original)

        source.available = [other, replacement]

        #expect(resolver.resolve() === replacement)
    }

    @Test func releasesOldScreenAndResolvesItsReplacement() {
        let source = Screens()
        var original: Screen? = Screen(7)
        weak let releasedScreen = original
        let resolver = source.resolver()
        resolver.select(original!)
        original = nil
        let replacement = Screen(7)
        source.available = [replacement]

        #expect(releasedScreen == nil)
        #expect(resolver.resolve() === replacement)
    }

    @Test func recoversAfterScreensAreTemporarilyUnavailable() {
        let source = Screens()
        let original = Screen(3)
        let resolver = source.resolver()
        resolver.select(original)

        #expect(resolver.resolve() == nil)

        let replacement = Screen(3)
        source.available = [Screen(4), replacement]
        #expect(resolver.resolve() === replacement)
    }

    @Test func switchesToAnotherNotchedDisplayWhenSelectedDisplayDisappears() {
        let source = Screens()
        let resolver = source.resolver()
        resolver.select(Screen(1))
        let external = Screen(2, hasNotch: false)
        let replacement = Screen(3)
        source.available = [external, replacement]

        #expect(resolver.resolve() === replacement)
        #expect(resolver.selectedDisplayID == 3)
    }

    @Test func skipsSelectedDisplayWhenItNoLongerHasANotch() {
        let source = Screens()
        let resolver = source.resolver()
        resolver.select(Screen(1))
        let replacement = Screen(2)
        source.available = [Screen(1, hasNotch: false), replacement]

        #expect(resolver.resolve() === replacement)
    }

    @Test func returnsNilWhenNoDisplayHasANotch() {
        let source = Screens()
        let resolver = source.resolver()
        resolver.select(Screen(1))
        source.available = [Screen(1, hasNotch: false), Screen(2, hasNotch: false)]

        #expect(resolver.resolve() == nil)
    }

    @Test func fallsBackWhenDisplayIdentifierIsUnavailable() {
        let source = Screens()
        let resolver = source.resolver()
        resolver.select(Screen(nil))
        let screen = Screen(nil)
        source.available = [Screen(4, hasNotch: false), screen]

        #expect(resolver.resolve() === screen)
    }

    @Test func resetRemovesPreviousDisplayPreference() {
        let source = Screens()
        let first = Screen(1)
        let second = Screen(2)
        source.available = [first, second]
        let resolver = source.resolver()
        resolver.select(second)
        resolver.reset()

        #expect(resolver.resolve() === first)
    }
}
