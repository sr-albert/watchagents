import Foundation

/// Everything the user has set about the farm, persisted across launches.
///
/// Named `OverloadSettings` until it held five fields, four of which had nothing to do with
/// overload. The `UserDefaults` keys are unchanged by that rename — they are the stored
/// contract, and renaming them would silently reset every existing user's preferences.
@MainActor
final class FarmSettings: ObservableObject {
    private static let storageKey = "overloadBasis"
    private static let dormantKey = "dormantAfterHours"
    private static let tokenCeilingKey = "tokenCeiling"
    private static let dollarCeilingKey = "dollarCeiling"
    private static let seededKey = "ceilingsSeeded"

    private let defaults: UserDefaults

    @Published var basis: OverloadBasis {
        didSet { defaults.set(basis.rawValue, forKey: Self.storageKey) }
    }

    /// Hours of terminal idle before a session is bedded down. Stored in hours because
    /// that is what the control offers; `Thresholds.dormantDuration` remains the canonical
    /// value in seconds, and is the default when nothing has been stored.
    @Published var dormantAfterHours: Double {
        didSet { defaults.set(dormantAfterHours, forKey: Self.dormantKey) }
    }

    /// Tokens the farm treats as one block's budget. The straw bales empty against this.
    @Published var tokenCeiling: Int {
        didSet { defaults.set(tokenCeiling, forKey: Self.tokenCeilingKey) }
    }

    /// Dollars the farm treats as one block's budget. The vat fills against this.
    @Published var dollarCeiling: Double {
        didSet { defaults.set(dollarCeiling, forKey: Self.dollarCeilingKey) }
    }

    /// Whether the ceilings have been seeded from observed history. Load-bearing: without it
    /// a later, heavier block would raise the ceilings and the bales would refill — which is
    /// the moving denominator this whole design exists to reject.
    @Published private(set) var ceilingsSeeded: Bool {
        didSet { defaults.set(ceilingsSeeded, forKey: Self.seededKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: Self.storageKey)
        basis = stored.flatMap(OverloadBasis.init) ?? .both
        // `double(forKey:)` returns 0 for a missing key, which would bed down every
        // session instantly — so absence is checked explicitly rather than by falsiness.
        dormantAfterHours = defaults.object(forKey: Self.dormantKey) as? Double
            ?? Thresholds.dormantDuration / 3600
        // Unlike `dormantAfterHours`, a missing key and a "not yet seeded" ceiling mean the
        // same thing here, so the 0-default from `integer(forKey:)`/`double(forKey:)` is
        // correct as-is — `ceilingsSeeded` is the authority regardless.
        tokenCeiling = defaults.integer(forKey: Self.tokenCeilingKey)
        dollarCeiling = defaults.double(forKey: Self.dollarCeilingKey)
        ceilingsSeeded = defaults.bool(forKey: Self.seededKey)
    }

    /// Seeds both ceilings from the heaviest block on record, once and only once.
    ///
    /// Called on every poll and does nothing after the first success — the flag, not the
    /// caller, is what guarantees that. Zeros mean `ccusage` has no history yet, so seeding
    /// waits rather than locking the ceiling at zero.
    func seedCeilingsIfNeeded(observedMaxTokens: Int, observedMaxCost: Double) {
        guard !ceilingsSeeded, observedMaxTokens > 0, observedMaxCost > 0 else { return }
        tokenCeiling = observedMaxTokens
        dollarCeiling = observedMaxCost
        ceilingsSeeded = true
    }

    /// The barn's only way to record a deliberate edit. Writes both ceilings and marks
    /// them seeded in one call, so the three can never land in a partial state — an edit
    /// to one field alone, made before the first seed, used to leave `ceilingsSeeded`
    /// false and get silently overwritten by the next successful seed. Callers pass the
    /// field being edited and the *current* value of the other, so a token-only edit
    /// doesn't zero out the dollar ceiling and wedge `FeedGaugeReader`'s `> 0` guard shut
    /// forever. This also makes `ceilingsSeeded` the single authority for "configured" —
    /// `UsageBlockFetcher`'s own `tokenCeiling > 0` check is a second sentinel on the same
    /// question and should eventually defer to this one rather than drift independently.
    func configureCeilings(tokens: Int, dollars: Double) {
        tokenCeiling = tokens
        dollarCeiling = dollars
        ceilingsSeeded = true
    }
}
