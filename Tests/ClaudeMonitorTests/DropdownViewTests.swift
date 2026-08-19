import XCTest
import SwiftUI
@testable import ClaudeMonitor

final class DropdownViewTests: XCTestCase {
    /// A short list is as tall as its rows and no taller — the cap must not leave the
    /// popover mostly empty whenever fewer than eight sessions are running.
    func test_aShortListIsSizedToItsRows() {
        XCTAssertEqual(DropdownView.listHeight(for: 0), 0)
        XCTAssertEqual(DropdownView.listHeight(for: 3), 3 * DropdownView.rowHeight)
    }

    /// The bug this exists for: 20 processes (one ordinary day with worktrees) grew the
    /// popover past the height of the screen, pushing the usage block and every control
    /// below it out of reach.
    func test_aLongListStopsAtTheCap() {
        XCTAssertEqual(DropdownView.listHeight(for: 20), DropdownView.maxListHeight)
        XCTAssertEqual(DropdownView.listHeight(for: 500), DropdownView.maxListHeight)
    }

    /// The cap has to leave room for everything underneath it. ~330pt of fixed chrome
    /// sits above and below the list; 640pt total is comfortable on the shortest display
    /// this app runs on.
    func test_theCapLeavesRoomForTheControlsBelowIt() {
        XCTAssertLessThanOrEqual(DropdownView.maxListHeight + 330, 640)
    }

    /// `MonitorViewModel.snapshot` is `private(set)` and only polling fills it, so this
    /// covers the empty case only — the populated list is covered by the height rule
    /// above, which is where the bug was.
    @MainActor
    func test_dropdown_bodyEvaluatesBeforeTheFirstPollLands() {
        _ = DropdownView(viewModel: MonitorViewModel(),
                         settings: FarmSettings()).body
    }
}
