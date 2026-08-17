import Foundation

/// The farm's user-set preferences. Named for the overload basis it originally held; it
/// now also carries the dormancy threshold, and a rename to `FarmSettings` was deferred
/// rather than widen this feature's diff across five files. If a third setting arrives,
/// rename it then — do not add a second settings object beside this one.
@MainActor
final class OverloadSettings: ObservableObject {
    private static let storageKey = "overloadBasis"
    private static let dormantKey = "dormantAfterHours"

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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: Self.storageKey)
        basis = stored.flatMap(OverloadBasis.init) ?? .both
        // `double(forKey:)` returns 0 for a missing key, which would bed down every
        // session instantly — so absence is checked explicitly rather than by falsiness.
        dormantAfterHours = defaults.object(forKey: Self.dormantKey) as? Double
            ?? Thresholds.dormantDuration / 3600
    }
}
