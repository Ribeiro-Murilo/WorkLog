import SwiftUI

struct NotchContentView<ExpandedContent: View>: View {
    let isExpanded: Bool
    @ViewBuilder var expandedContent: () -> ExpandedContent

    init(
        isExpanded: Bool,
        @ViewBuilder expandedContent: @escaping () -> ExpandedContent = { EmptyView() }
    ) {
        self.isExpanded = isExpanded
        self.expandedContent = expandedContent
    }

    var body: some View {
        ZStack {
            if isExpanded {
                NotchVisualEffectView()
                    .clipShape(NotchShape(cornerRadius: 20))
                    .overlay(NotchShape(cornerRadius: 20).fill(Color.black.opacity(0.35)))
            } else {
                NotchVisualEffectView()
                    .clipShape(NotchShape())
                    .overlay(NotchShape().fill(Color.black.opacity(0.6)))
            }

            if isExpanded {
                expandedContent()
                    .opacity(isExpanded ? 1 : 0)
            } else {
                Circle()
                    .fill(.white.opacity(0.6))
                    .frame(width: 4, height: 4)
                    .opacity(isExpanded ? 0 : 1)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isExpanded)
    }
}
