import XCTest
@testable import ClaudeMonitor

final class FormattingTests: XCTestCase {
    func test_tokens_underThousand_returnsRawNumber() {
        XCTAssertEqual(Formatting.tokens(500), "500")
    }

    func test_tokens_thousands_returnsKSuffix() {
        XCTAssertEqual(Formatting.tokens(45_000), "45k")
    }

    func test_tokens_thousands_roundsRatherThanTruncates() {
        XCTAssertEqual(Formatting.tokens(45_900), "46k")
        XCTAssertEqual(Formatting.tokens(45_400), "45k")
    }

    func test_tokens_millions_returnsMSuffixWithTwoDecimals() {
        XCTAssertEqual(Formatting.tokens(2_500_000), "2.50M")
    }

    func test_duration_formatsHoursAndMinutes() {
        XCTAssertEqual(Formatting.duration(minutes: 83), "1h23m")
    }

    func test_duration_negativeClampsToZero() {
        XCTAssertEqual(Formatting.duration(minutes: -5), "0h00m")
    }
}
