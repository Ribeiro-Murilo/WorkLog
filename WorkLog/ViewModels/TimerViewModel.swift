import Foundation
import Observation

@MainActor
@Observable
final class TimerViewModel {
    private let timerService: TimerServiceProtocol
    private let settingsRepository: SettingsRepositoryProtocol

    var errorMessage: String?

    var activeProject: Project? { timerService.activeProject }
    var isRunning: Bool { timerService.isRunning }
    var elapsed: TimeInterval { timerService.elapsed }

    var elapsedFormatted: String {
        let showSeconds = (try? settingsRepository.current().showSeconds) ?? true
        return elapsed.formattedClock(showSeconds: showSeconds)
    }

    init(timerService: TimerServiceProtocol, settingsRepository: SettingsRepositoryProtocol) {
        self.timerService = timerService
        self.settingsRepository = settingsRepository
    }

    func start(project: Project) {
        do {
            try timerService.start(project: project)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func pause() {
        do {
            try timerService.pause()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resume() {
        do {
            try timerService.resume()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        do {
            try timerService.stop()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addManualSession(project: Project, startTime: Date, endTime: Date, note: String) {
        do {
            try timerService.addManualSession(project: project, startTime: startTime, endTime: endTime, note: note)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
