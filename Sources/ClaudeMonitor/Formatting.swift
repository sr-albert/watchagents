import Foundation

enum Formatting {
    static func tokens(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.2fM", Double(n) / 1_000_000)
        } else if n >= 1_000 {
            // Round rather than truncate, matching the original script's `f'{n/1_000:.0f}k'`.
            return String(format: "%.0fk", Double(n) / 1_000)
        } else {
            return "\(n)"
        }
    }

    static func duration(minutes: Int) -> String {
        let clamped = max(0, minutes)
        let hrs = clamped / 60
        let mins = clamped % 60
        return String(format: "%dh%02dm", hrs, mins)
    }
}
