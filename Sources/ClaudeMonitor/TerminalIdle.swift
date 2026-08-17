import Foundation

/// How long since each terminal last received input, read from `w`.
///
/// Its own type because the parsing is the risky part. `w`'s idle column has four shapes,
/// and a parser that understands only `HH:MM` reads `3days` as unparseable, falls back to
/// "not idle", and leaves the most dormant sessions on the machine awake — a silent
/// failure in the one direction that defeats the feature.
enum TerminalIdle {
    /// Seconds, or `nil` for a shape this code does not recognise. Deliberately not `0`
    /// on failure: `0` means "active right now", so an unrecognised `w` format would make
    /// every session look freshly used. `nil` never satisfies a threshold, which leaves
    /// the farm behaving exactly as it did before this feature existed.
    static func parseIdleField(_ field: String) -> TimeInterval? {
        if field == "-" { return 0 }

        // Checked longest-first: "days" must not be matched by the "day" branch.
        for suffix in ["days", "day"] where field.hasSuffix(suffix) {
            guard let days = Double(field.dropLast(suffix.count)) else { return nil }
            return days * 86400
        }

        if field.contains(":") {
            let parts = field.split(separator: ":")
            guard parts.count == 2,
                  let hours = Double(parts[0]),
                  let minutes = Double(parts[1]) else { return nil }
            return hours * 3600 + minutes * 60
        }

        guard let minutes = Double(field) else { return nil }
        return minutes * 60
    }

    /// Short tty name (`"s017"`, as both `w` and `ps aux` write it) to idle seconds.
    ///
    /// `w -h` omits the header, so every line is a session:
    /// `USER TTY FROM LOGIN@ IDLE WHAT`. Only field 4 is read — `WHAT` may contain
    /// spaces, and nothing past `IDLE` matters.
    static func parse(_ output: String) -> [String: TimeInterval] {
        var result: [String: TimeInterval] = [:]
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard fields.count >= 5, let idle = parseIdleField(fields[4]) else { continue }
            result[fields[1]] = idle
        }
        return result
    }
}
