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
