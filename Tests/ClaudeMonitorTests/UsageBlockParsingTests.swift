import XCTest
@testable import ClaudeMonitor

final class UsageBlockParsingTests: XCTestCase {
    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    func test_parse_activeBlock_computesPctAndFormatsFields() {
        let json = """
        {
          "blocks": [
            {
              "totalTokens": 40000,
              "costUSD": 1.5,
              "isActive": false,
              "startTime": "2026-08-13T08:00:00Z",
              "endTime": "2026-08-13T13:00:00Z"
            },
            {
              "totalTokens": 20000,
              "costUSD": 0.75,
              "isActive": true,
              "burnRate": {"tokensPerMinute": 250},
              "projection": {"totalCost": 3.0},
              "startTime": "2026-08-13T09:00:00Z",
              "endTime": "2026-08-13T14:00:00Z"
            }
          ]
        }
        """.data(using: .utf8)!

        let now = isoFormatter.date(from: "2026-08-13T12:30:00Z")!

        let result = UsageBlockParsing.parse(json, now: now)

        guard case .active(let block) = result else {
            return XCTFail("expected active block, got \(result)")
        }
        XCTAssertEqual(block.pct, 50) // 20000 / max(40000, 20000) = 50%
        XCTAssertEqual(block.usedTokens, "20k")
        XCTAssertEqual(block.maxTokens, "40k")
        XCTAssertEqual(block.cost, 0.75)
        XCTAssertEqual(block.burnRate, "250")
        XCTAssertEqual(block.estimatedCost, 3.0)
        XCTAssertEqual(block.resetIn, "1h30m") // 14:00 - 12:30
    }

    /// Real `npx ccusage blocks --json` output carries fractional seconds on every
    /// timestamp and explicit `null`s for absent burnRate/projection. A formatter
    /// configured with `.withInternetDateTime` alone returns nil for those, which made
    /// the whole feature return `.unavailable` in production while ms-free fixtures passed.
    func test_parse_activeBlock_withFractionalSecondTimestamps_parsesLikeRealCcusageOutput() {
        let json = """
        {
          "blocks": [
            {
              "totalTokens": 40000,
              "costUSD": 1.5,
              "isActive": false,
              "isGap": false,
              "burnRate": null,
              "projection": null,
              "startTime": "2026-08-13T04:00:00.000Z",
              "endTime": "2026-08-13T09:00:00.000Z"
            },
            {
              "totalTokens": 20000,
              "costUSD": 0.75,
              "isActive": true,
              "isGap": false,
              "burnRate": {"tokensPerMinute": 250},
              "projection": {"totalCost": 3.0},
              "startTime": "2026-08-13T09:00:00.000Z",
              "endTime": "2026-08-13T14:00:00.000Z"
            }
          ]
        }
        """.data(using: .utf8)!

        let now = isoFormatter.date(from: "2026-08-13T12:30:00Z")!

        let result = UsageBlockParsing.parse(json, now: now)

        guard case .active(let block) = result else {
            return XCTFail("expected active block, got \(result)")
        }
        XCTAssertEqual(block.pct, 50)
        XCTAssertEqual(block.usedTokens, "20k")
        XCTAssertEqual(block.maxTokens, "40k")
        XCTAssertEqual(block.resetIn, "1h30m")
    }

    func test_date_fromISO8601_acceptsBothFractionalAndPlainTimestamps() {
        XCTAssertEqual(
            UsageBlockParsing.date(fromISO8601: "2026-08-13T09:00:00.000Z"),
            UsageBlockParsing.date(fromISO8601: "2026-08-13T09:00:00Z")
        )
        XCTAssertNotNil(UsageBlockParsing.date(fromISO8601: "2026-08-13T09:00:00.000Z"))
        XCTAssertNotNil(UsageBlockParsing.date(fromISO8601: "2026-08-13T09:00:00Z"))
        XCTAssertNil(UsageBlockParsing.date(fromISO8601: "not a date"))
    }

    func test_parse_noActiveBlock_returnsNoActiveBlock() {
        let json = """
        {"blocks": [{"totalTokens": 100, "costUSD": 0, "isActive": false, "startTime": "2026-08-13T08:00:00Z", "endTime": "2026-08-13T09:00:00Z"}]}
        """.data(using: .utf8)!

        XCTAssertEqual(UsageBlockParsing.parse(json, now: Date()), .noActiveBlock)
    }

    func test_parse_malformedJSON_returnsUnavailable() {
        let json = "not json".data(using: .utf8)!

        XCTAssertEqual(UsageBlockParsing.parse(json, now: Date()), .unavailable)
    }
}
