enum NotchHoverPolicy {
    static func shouldExpand(isExpanded: Bool, isPinned: Bool, isEditing: Bool,
                             containsExpanded: Bool, containsCollapsed: Bool) -> Bool {
        containsCollapsed || (isExpanded && (isPinned || isEditing || containsExpanded))
    }
}
