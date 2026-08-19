import Foundation

/// What the farmyard shows about the current block: how many bales still stand, and how full
/// the vat is. Three of each, so the two read at the same resolution and a disagreement
/// between them is visible.
struct FeedGauge: Equatable {
    /// 0...3 bales standing. 3 means the budget is untouched.
    let bales: Int
    /// 0...3 filled rows in the vat. 3 means the budget is spent.
    let vat: Int
}

enum FeedGaugeReader {
    /// Bales and vat are deliberately mirrored — `ceil` on what remains, `floor` on what is
    /// spent — so neither reads finished before it is. They divide by *different* ceilings on
    /// purpose: tokens and dollars are reported independently, so the gap between the two
    /// gauges is the useful signal (expensive models, or poor cache hits).
    ///
    /// Returns `nil` when there is nothing to say — no `ccusage`, or ceilings not yet seeded.
    /// The caller must draw NO props for `nil`, which is not the same as drawing an empty
    /// gauge: absent means "nothing to tell you", empty means "you have nothing left".
    static func gauge(for result: UsageBlockResult,
                      tokenCeiling: Int,
                      dollarCeiling: Double) -> FeedGauge? {
        guard tokenCeiling > 0, dollarCeiling > 0 else { return nil }

        switch result {
        case .unavailable:
            return nil
        case .noActiveBlock:
            // A block that has not started has spent nothing. True, not a placeholder.
            return FeedGauge(bales: 3, vat: 0)
        case .active(let block):
            return FeedGauge(bales: bales(spent: block.rawTokens, ceiling: tokenCeiling),
                             vat: vat(spent: block.cost, ceiling: dollarCeiling))
        }
    }

    private static func bales(spent: Int, ceiling: Int) -> Int {
        let remaining = max(0, ceiling - spent)
        guard remaining > 0 else { return 0 }
        // `ceil`, so a single remaining token still stands a bale up.
        return min(3, Int(ceil(3.0 * Double(remaining) / Double(ceiling))))
    }

    private static func vat(spent: Double, ceiling: Double) -> Int {
        // Not redundant with the `min(3, …)` below, despite appearances: without this
        // guard, an over-spent block runs `Int(floor(3.0 * spent / ceiling))` on an
        // unbounded ratio, and `Int(_:)` on a `Double` past `Int.max` traps rather than
        // clamping. `bales` needs no equivalent guard because `remaining <= ceiling`
        // already bounds its ratio at 1 by construction; `spent` here has no such bound.
        guard spent < ceiling else { return 3 }
        // `floor`, so a cent short of the ceiling is not a full vat.
        return max(0, min(3, Int(floor(3.0 * spent / ceiling))))
    }
}
