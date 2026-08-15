import Foundation

@MainActor
final class OverloadSettings: ObservableObject {
    private static let storageKey = "overloadBasis"

    private let defaults: UserDefaults

    @Published var basis: OverloadBasis {
        didSet { defaults.set(basis.rawValue, forKey: Self.storageKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: Self.storageKey)
        basis = stored.flatMap(OverloadBasis.init) ?? .both
    }
}
