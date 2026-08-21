import XCTest
import SwiftUI
@testable import ClaudeMonitor

final class FarmCardSelectionTests: XCTestCase {
    func test_nothingHoveredOrPinnedShowsNoCard() {
        XCTAssertNil(FarmCardSelection.shownPID(hovered: nil, pinned: nil))
    }

    func test_hoveringAnAnimalShowsItsCardWithoutClicking() {
        XCTAssertEqual(FarmCardSelection.shownPID(hovered: 42, pinned: nil), 42)
    }

    /// Clicking pins the card so it survives the pointer leaving the animal — otherwise
    /// there is no way to read it and then go and do something with what it said.
    func test_aPinnedCardSurvivesThePointerLeaving() {
        XCTAssertEqual(FarmCardSelection.shownPID(hovered: nil, pinned: 42), 42)
    }

    /// Pointing at something beats having pinned something else. The pointer is the more
    /// recent statement of intent, and a pin that ignored it would make the farm feel
    /// stuck.
    func test_hoveringAnotherAnimalWinsOverThePin() {
        XCTAssertEqual(FarmCardSelection.shownPID(hovered: 7, pinned: 42), 7)
    }

    /// The close button belongs to the pin. On a hover card it cannot be reached —
    /// travelling to the corner leaves the animal and the card is gone before you arrive.
    func test_onlyThePinnedAnimalsCardOffersAClose() {
        XCTAssertTrue(FarmCardSelection.isDismissable(shown: 42, pinned: 42))
        XCTAssertFalse(FarmCardSelection.isDismissable(shown: 7, pinned: 42))
        XCTAssertFalse(FarmCardSelection.isDismissable(shown: 7, pinned: nil))
        XCTAssertFalse(FarmCardSelection.isDismissable(shown: nil, pinned: 42))
    }

    @MainActor
    func test_card_bodyEvaluatesWithAndWithoutAClose() {
        let process = ClaudeProcess(pid: 900, cpu: 1.5, mem: 0.5, cwd: "/tmp/x")
        _ = FarmDetailCard(process: process, onClose: {}).body
        _ = FarmDetailCard(process: process, onClose: nil).body
    }
}
