import Foundation

extension TimeInterval {
    /// Formata como "HH:MM:SS" ou "HH:MM" dependendo da preferência de segundos.
    func formattedClock(showSeconds: Bool) -> String {
        let totalSeconds = max(0, Int(self))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return showSeconds
            ? String(format: "%02d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", hours, minutes)
    }

    /// Formato compacto para a Menu Bar: "MM:SS" abaixo de uma hora, "H:MM:SS" acima.
    func compactMenuBarString(showSeconds: Bool) -> String {
        let totalSeconds = max(0, Int(self))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return showSeconds
                ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
                : String(format: "%d:%02d", hours, minutes)
        }
        return showSeconds
            ? String(format: "%02d:%02d", minutes, seconds)
            : String(format: "%02d min", minutes)
    }
}
