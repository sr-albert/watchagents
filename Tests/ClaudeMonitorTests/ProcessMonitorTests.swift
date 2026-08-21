import XCTest
@testable import ClaudeMonitor

final class ProcessMonitorTests: XCTestCase {
    func test_parsePS_matchesClaudeLines_andExcludesSelf() {
        let output = """
        USER   PID  %CPU %MEM    VSZ   RSS TTY STAT START   TIME COMMAND
        albert 501  12.3  1.5 123456 45678 ??  S    9:00AM 0:12.34 claude
        albert 777   0.1  0.2 111111 22222 ??  S    9:01AM 0:01.00 /Applications/ClaudeMonitor.app/Contents/MacOS/ClaudeMonitor
        albert 900   2.0  0.4  99999 33333 ??  S    9:02AM 0:00.50 /bin/zsh -c ls
        albert 950   0.0  0.0  88888 11111 s007 S+  9:03AM 0:09.44 bash /Users/albert/.local/bin/claude-monitor
        """

        // Mirrors the exclusion list ProcessMonitor.snapshot() actually passes, including
        // the hyphenated legacy bash script.
        let result = ProcessParsing.parsePS(
            output,
            excludingProcessNames: ["claudemonitor", "claude-monitor"]
        )

        XCTAssertEqual(result, [ClaudeProcess(pid: 501, cpu: 12.3, mem: 1.5)])
    }

    func test_parseCWD_extractsPathFromLsofOutput() {
        let output = "p501\nfcwd\nn/Users/albert/Projects/watchagents\n"

        XCTAssertEqual(ProcessParsing.parseCWD(output), "/Users/albert/Projects/watchagents")
    }

    func test_parseCWD_returnsNil_whenNoCwdLine() {
        let output = "p501\nfcwd\n"

        XCTAssertNil(ProcessParsing.parseCWD(output))
    }

    func test_snapshot_computesTotalsAndUniqueSessionCount() {
        let processes = [
            ClaudeProcess(pid: 1, cpu: 10.0, mem: 1.0, cwd: "/a"),
            ClaudeProcess(pid: 2, cpu: 5.0, mem: 0.5, cwd: "/a"),
            ClaudeProcess(pid: 3, cpu: 2.0, mem: 0.2, cwd: "/b"),
        ]

        let snapshot = ProcessParsing.snapshot(from: processes)

        XCTAssertEqual(snapshot.cpuTotal, 17.0, accuracy: 0.001)
        XCTAssertEqual(snapshot.memTotal, 1.7, accuracy: 0.001)
        XCTAssertEqual(snapshot.sessionCount, 2)
        XCTAssertEqual(snapshot.processes.count, 3)
    }

    func test_claudeProcess_defaultsStateToIdle() {
        let process = ClaudeProcess(pid: 42, cpu: 1.0, mem: 1.0)

        XCTAssertEqual(process.state, .idle)
    }

    func test_parsePS_readsTheTTYColumn() {
        let output = """
        albert 501  12.3  1.5 123456 45678 s017 S+   9:00AM 0:12.34 claude
        albert 502   0.5  0.3 123456 45678 ??   S    9:00AM 0:12.34 claude
        """

        let result = ProcessParsing.parsePS(output, excludingProcessNames: [])

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].tty, "s017")
        // "??" is ps's no-controlling-terminal marker, not a tty name. A process with no
        // terminal has no terminal idle time and can never be dormant.
        XCTAssertNil(result[1].tty)
    }

    /// A real `ps aux` line always carries 11 fields, so raising the floor from 4 to 7 can
    /// only reject malformed input — never a genuine tty-less process, which still gets
    /// all 11 with `??` in the TTY column.
    func test_parsePS_skipsLinesTooShortToHoldATTY() {
        let output = "albert 501 12.3 1.5 claude\n"
        XCTAssertTrue(ProcessParsing.parsePS(output, excludingProcessNames: []).isEmpty)
    }
}
