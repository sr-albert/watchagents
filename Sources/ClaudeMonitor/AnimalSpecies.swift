import Foundation

enum AnimalSpecies: String, CaseIterable {
    case cow = "🐄"
    case pig = "🐖"
    case sheep = "🐑"
    case chicken = "🐔"
    case horse = "🐴"
    case llama = "🦙"
    case goat = "🐐"
}

enum AnimalAssignment {
    private static let fnvOffsetBasis: UInt64 = 0xcbf29ce484222325
    private static let fnvPrime: UInt64 = 0x100000001b3

    /// FNV-1a (64-bit) over the string's UTF-8 bytes. Deliberately not Swift's
    /// built-in `String.hashValue`/`Hasher`, which reseeds randomly every process
    /// launch (a hash-flooding mitigation) and would reassign every project a new
    /// species on every app restart.
    static func stableHash(_ string: String) -> UInt64 {
        var hash = fnvOffsetBasis
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            // `&*` (wrapping multiply) is required here, not `*` — FNV-1a's
            // multiplication is defined modulo 2^64, and a plain `*` traps on
            // overflow in Swift instead of wrapping.
            hash = hash &* fnvPrime
        }
        return hash
    }

    static func species(forCWD cwd: String) -> AnimalSpecies {
        let cases = AnimalSpecies.allCases
        let index = Int(stableHash(cwd) % UInt64(cases.count))
        return cases[index]
    }
}
