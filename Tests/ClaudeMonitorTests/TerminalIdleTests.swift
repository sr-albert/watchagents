import XCTest
@testable import ClaudeMonitor

final class TerminalIdleTests: XCTestCase {
    func test_parseIdleField_handlesEveryFormWWrites() {
        XCTAssertEqual(TerminalIdle.parseIdleField("-"), 0)
        XCTAssertEqual(TerminalIdle.parseIdleField("19"), 1140)
        XCTAssertEqual(TerminalIdle.parseIdleField("11:50"), 42600)
        XCTAssertEqual(TerminalIdle.parseIdleField("5days"), 432000)
        XCTAssertEqual(TerminalIdle.parseIdleField("1day"), 86400)
    }

    /// nil, not 0: an unrecognised format must leave the farm behaving as it does today,
    /// and nil never satisfies a threshold. Returning 0 would be indistinguishable from
    /// "active right now", which is the wrong direction to fail in.
    func test_parseIdleField_returnsNilForUnrecognisedForms() {
        XCTAssertNil(TerminalIdle.parseIdleField("wat"))
        XCTAssertNil(TerminalIdle.parseIdleField(""))
        XCTAssertNil(TerminalIdle.parseIdleField("1:2:3"))
        XCTAssertNil(TerminalIdle.parseIdleField("xdays"))
    }

    func test_parse_mapsShortTTYNamesToSeconds() {
        let output = """
        albert     console  -      Tue07   5days -
        albert     s000     -      Sun08   23:04 -zsh
        albert     s004     -      Sat23       - node
        albert     s008     -      Sun14      19 /usr/bin/less
        albert     s009     -      Sat22   11:50 node
        """

        let result = TerminalIdle.parse(output)

        XCTAssertEqual(result["console"], 432000)   // 5 * 86400
        XCTAssertEqual(result["s000"], 83040)       // 23 * 3600 + 4 * 60
        XCTAssertEqual(result["s004"], 0)
        XCTAssertEqual(result["s008"], 1140)        // 19 * 60
        XCTAssertEqual(result["s009"], 42600)       // 11 * 3600 + 50 * 60
    }

    /// WHAT is the last column and may contain spaces; nothing past IDLE is read.
    func test_parse_ignoresSpacesInTheCommandColumn() {
        let output = "albert s002 - Thu09 3days tail -f .dev-logs/server.log .dev-logs\n"
        XCTAssertEqual(TerminalIdle.parse(output)["s002"], 259200)
    }

    func test_parse_skipsLinesItCannotRead() {
        let output = """
        albert     s001     -      Sun08   wat   -zsh
        short line
        albert     s002     -      Sun08   19    -zsh
        """
        let result = TerminalIdle.parse(output)
        XCTAssertNil(result["s001"])
        XCTAssertEqual(result["s002"], 1140)
        XCTAssertEqual(result.count, 1)
    }
}
