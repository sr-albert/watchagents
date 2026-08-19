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

        let result = UsageBlockParsing.parse(json, now: now, tokenCeiling: 0)

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

        let result = UsageBlockParsing.parse(json, now: now, tokenCeiling: 0)

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

        XCTAssertEqual(UsageBlockParsing.parse(json, now: Date(), tokenCeiling: 0), .noActiveBlock)
    }

    func test_parse_malformedJSON_returnsUnavailable() {
        let json = "not json".data(using: .utf8)!

        XCTAssertEqual(UsageBlockParsing.parse(json, now: Date(), tokenCeiling: 0), .unavailable)
    }

    /// Two blocks, one active. The observed maxima come from ALL blocks, because they exist
    /// only to seed the ceilings; the displayed denominator comes from the ceiling passed in.
    private func twoBlockFixture() -> Data {
        """
        {"blocks":[
          {"totalTokens":900,"costUSD":9.0,"isActive":false,
           "startTime":"2026-08-18T00:00:00.000Z","endTime":"2026-08-18T05:00:00.000Z"},
          {"totalTokens":300,"costUSD":2.0,"isActive":true,
           "startTime":"2026-08-18T05:00:00.000Z","endTime":"2026-08-18T10:00:00.000Z"}
        ]}
        """.data(using: .utf8)!
    }

    func test_parseExposesRawTokensAndTheObservedMaxima() {
        let now = ISO8601DateFormatter().date(from: "2026-08-18T06:00:00Z")!
        guard case .active(let b) = UsageBlockParsing.parse(twoBlockFixture(), now: now,
                                                            tokenCeiling: 1000) else {
            return XCTFail("expected an active block")
        }
        XCTAssertEqual(b.rawTokens, 300)
        XCTAssertEqual(b.observedMaxTokens, 900)
        XCTAssertEqual(b.observedMaxCost, 9.0, accuracy: 0.0001)
    }

    /// The denominator is the configured ceiling, not the heaviest block. With a ceiling of
    /// 1000 and 300 spent, that is 30% — against the old observed-max denominator it would
    /// have read 33%, so this test fails if the demotion is not done.
    func test_percentageIsAgainstTheConfiguredCeiling() {
        let now = ISO8601DateFormatter().date(from: "2026-08-18T06:00:00Z")!
        guard case .active(let b) = UsageBlockParsing.parse(twoBlockFixture(), now: now,
                                                            tokenCeiling: 1000) else {
            return XCTFail("expected an active block")
        }
        XCTAssertEqual(b.pct, 30)
    }

    /// Before seeding there is no ceiling. Falling back to the observed maximum keeps the
    /// storehouse sensible on a first run rather than dividing by zero.
    func test_anUnsetCeilingFallsBackToTheObservedMaximum() {
        let now = ISO8601DateFormatter().date(from: "2026-08-18T06:00:00Z")!
        guard case .active(let b) = UsageBlockParsing.parse(twoBlockFixture(), now: now,
                                                            tokenCeiling: 0) else {
            return XCTFail("expected an active block")
        }
        XCTAssertEqual(b.pct, 33)
    }
}
