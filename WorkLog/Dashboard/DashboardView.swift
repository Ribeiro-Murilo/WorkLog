import SwiftUI

struct DashboardView: View {
    @State private var selection: DashboardSidebarSection? = .summary

    var body: some View {
        NavigationSplitView {
            List(DashboardSidebarSection.allCases, selection: $selection) { section in
                Label(section.displayName, systemImage: section.symbolName)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            switch selection {
            case .summary, .none:
                DashboardHomeView()
            case .projects:
                ProjectListView()
            case .reports:
                ReportsView()
            }
        }
        .frame(minWidth: 760, minHeight: 480)
    }
}
