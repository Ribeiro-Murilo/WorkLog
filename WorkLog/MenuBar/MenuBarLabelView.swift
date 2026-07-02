import SwiftUI

struct MenuBarLabelView: View {
    @Environment(\.dependencies) private var dependencies
    @State private var viewModel: MenuBarViewModel?

    var body: some View {
        Group {
            if let title = viewModel?.menuBarTitle {
                Text(title)
            } else {
                Image(systemName: "clock")
            }
        }
        .task {
            if viewModel == nil {
                viewModel = MenuBarViewModel(
                    timerService: dependencies.timerService,
                    projectRepository: dependencies.projectRepository,
                    sessionRepository: dependencies.sessionRepository,
                    settingsRepository: dependencies.settingsRepository
                )
            }
        }
    }
}
