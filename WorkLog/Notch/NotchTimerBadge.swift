import SwiftUI

/// Badge exibido à direita do notch quando colapsado: mostra o tempo do timer em
/// execução (horas/minutos) e desaparece quando nenhum timer está rodando.
struct NotchTimerBadge: View {
    @Environment(\.dependencies) private var dependencies
    @State private var viewModel: MenuBarViewModel?

    var body: some View {
        Group {
            if let elapsed = viewModel?.compactElapsed {
                Text(elapsed)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                Color.clear
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
