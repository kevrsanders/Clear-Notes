import Foundation

extension TimeInterval {
    /// "4:05" or "1:02:09".
    var clockString: String {
        let total = Int(self.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    /// "Under a minute", "1 min", "1 hr 5 min".
    var durationString: String {
        let minutes = Int((self / 60).rounded())
        if minutes < 1 { return "Under a minute" }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) hr" : "\(hours) hr \(rest) min"
    }
}
