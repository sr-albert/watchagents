import Foundation

struct ClaudeProcess: Equatable {
    let pid: Int
    let cpu: Double
    let mem: Double
    var cwd: String = "(unknown)"
    var state: SessionState = .idle
    /// When this session stopped working, from `SessionStateTracker`. The farm anchors a
    /// resting animal at the spot its walk ended, and this is the instant that walk
    /// ended — see `FarmAnimalPlacer.place`. Nil until a session has gone quiet, and for
    /// any caller that builds a `ClaudeProcess` without a tracker behind it.
    var idleSince: Date?
    /// Short name of the controlling terminal, as both `ps aux` and `w` write it
    /// (`"s017"`). Nil when `ps` reports `??` — no controlling terminal, which is what
    /// the menu-bar app itself shows.
    var tty: String?
    /// Seconds since this session's terminal last received input, from `w`. Nil when the
    /// process has no tty, when `w` does not list it, or when its idle column could not
    /// be parsed — see `TerminalIdle`. Nil never satisfies the dormancy threshold.
    var ttyIdle: TimeInterval?
}

struct ProcessSnapshot: Equatable {
    let processes: [ClaudeProcess]
    let cpuTotal: Double
    let memTotal: Double
    let sessionCount: Int
}

enum ProcessParsing {
    static func parsePS(_ output: String, excludingProcessNames: [String]) -> [ClaudeProcess] {
        var results: [ClaudeProcess] = []
        for line in output.split(separator: "\n") {
            let lower = line.lowercased()
            guard lower.contains("claude") else { continue }
            if excludingProcessNames.contains(where: { lower.contains($0.lowercased()) }) {
                continue
            }
            let fields = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            // Field 6 is `ps aux`'s TT column. Requiring it raises the old `>= 4` floor:
            // a line too short to hold a tty is malformed, not a tty-less process.
            guard fields.count >= 7,
                  let pid = Int(fields[1]),
                  let cpu = Double(fields[2]),
                  let mem = Double(fields[3]) else { continue }
            var process = ClaudeProcess(pid: pid, cpu: cpu, mem: mem)
            process.tty = fields[6] == "??" ? nil : fields[6]
            results.append(process)
        }
        return results
    }

    static func parseCWD(_ output: String) -> String? {
        for line in output.split(separator: "\n") {
            if line.hasPrefix("n/") {
                return String(line.dropFirst())
            }
        }
        return nil
    }

    static func snapshot(from processes: [ClaudeProcess]) -> ProcessSnapshot {
        let cpuTotal = processes.reduce(0) { $0 + $1.cpu }
        let memTotal = processes.reduce(0) { $0 + $1.mem }
        let uniqueCWDs = Set(processes.map { $0.cwd })
        return ProcessSnapshot(
            processes: processes,
            cpuTotal: cpuTotal,
            memTotal: memTotal,
            sessionCount: uniqueCWDs.count
        )
    }
}

final class ProcessMonitor {
    private func run(_ executable: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        // Discard stderr rather than buffering it unread: an unread pipe can fill the
        // OS buffer and deadlock `waitUntilExit()`.
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    func snapshot() -> ProcessSnapshot {
        let psOutput = run("/bin/ps", ["aux"])
        // "claude-monitor" is the legacy bash script (~/.local/bin/claude-monitor), which
        // stays installed during the transition and would otherwise be counted as a session.
        var processes = ProcessParsing.parsePS(
            psOutput,
            excludingProcessNames: ["claudemonitor", "claude-monitor"]
        )
        for i in processes.indices {
            let lsofOutput = run("/usr/sbin/lsof", ["-a", "-p", "\(processes[i].pid)", "-d", "cwd", "-Fn"])
            if let cwd = ProcessParsing.parseCWD(lsofOutput) {
                processes[i].cwd = cwd
            }
        }
        // One `w` for the whole sweep, unlike `lsof` above which is unavoidably per-pid.
        let idleByTTY = TerminalIdle.parse(run("/usr/bin/w", ["-h"]))
        for i in processes.indices {
            processes[i].ttyIdle = processes[i].tty.flatMap { idleByTTY[$0] }
        }
        return ProcessParsing.snapshot(from: processes)
    }
}
