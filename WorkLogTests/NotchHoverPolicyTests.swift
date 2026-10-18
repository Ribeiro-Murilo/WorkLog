import Testing
@testable import WorkLog

struct NotchHoverPolicyTests {
    @Test func pinAndTextEditingKeepExpandedPanelOpenOutsideHoverZones() {
        #expect(NotchHoverPolicy.shouldExpand(isExpanded: true, isPinned: true, isEditing: false,
                                              containsExpanded: false, containsCollapsed: false))
        #expect(NotchHoverPolicy.shouldExpand(isExpanded: true, isPinned: false, isEditing: true,
                                              containsExpanded: false, containsCollapsed: false))
        #expect(!NotchHoverPolicy.shouldExpand(isExpanded: true, isPinned: false, isEditing: false,
                                               containsExpanded: false, containsCollapsed: false))
    }

    @Test func collapsedPanelStillRequiresItsOwnHoverZone() {
        #expect(!NotchHoverPolicy.shouldExpand(isExpanded: false, isPinned: false, isEditing: false,
                                               containsExpanded: true, containsCollapsed: false))
        #expect(NotchHoverPolicy.shouldExpand(isExpanded: false, isPinned: false, isEditing: false,
                                              containsExpanded: false, containsCollapsed: true))
        #expect(NotchHoverPolicy.shouldExpand(isExpanded: true, isPinned: false, isEditing: false,
                                              containsExpanded: true, containsCollapsed: false))
    }
}
