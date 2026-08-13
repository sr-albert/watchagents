import Foundation

struct ClaudeProcess: Equatable {
    let pid: Int
    let cpu: Double
    let mem: Double
    var cwd: String = "(unknown)"
}

struct ProcessSnapshot {
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
            guard fields.count >= 4,
                  let pid = Int(fields[1]),
                  let cpu = Double(fields[2]),
                  let mem = Double(fields[3]) else { continue }
            results.append(ClaudeProcess(pid: pid, cpu: cpu, mem: mem))
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
        process.standardError = Pipe()
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
        var processes = ProcessParsing.parsePS(psOutput, excludingProcessNames: ["claudemonitor"])
        for i in processes.indices {
            let lsofOutput = run("/usr/sbin/lsof", ["-a", "-p", "\(processes[i].pid)", "-d", "cwd", "-Fn"])
            if let cwd = ProcessParsing.parseCWD(lsofOutput) {
                processes[i].cwd = cwd
            }
        }
        return ProcessParsing.snapshot(from: processes)
    }
}
