import Foundation

/// FNV-1a over integers. Deliberately not Swift's `Hasher`, which reseeds every process
/// launch — the scene must look identical across restarts, same reason the species hash
/// rolls its own.
enum StableHash {
    private static let offsetBasis: UInt64 = 0xcbf29ce484222325
    private static let prime: UInt64 = 0x100000001b3

    static func of(_ values: Int...) -> UInt64 {
        var hash = offsetBasis
        for value in values {
            // Bit-pattern conversion so negative coords hash without trapping.
            var bits = UInt64(bitPattern: Int64(value))
            for _ in 0..<8 {
                hash ^= bits & 0xff
                hash = hash &* prime
                bits >>= 8
            }
        }
        return hash
    }

    /// `hash % modulus` as an `Int`, for picking from a table.
    static func pick(_ modulus: Int, _ values: Int...) -> Int {
        var hash = offsetBasis
        for value in values {
            var bits = UInt64(bitPattern: Int64(value))
            for _ in 0..<8 {
                hash ^= bits & 0xff
                hash = hash &* prime
                bits >>= 8
            }
        }
        return Int(hash % UInt64(modulus))
    }
}

enum FarmGround {
    static let plain = 0
    static let tuft = 1
    static let flowers = 2

    /// Grass variation in *clumps*, not per-tile static. The coarse `clump` term (one
    /// value per 4×3 block) gates the fine term, so variation forms regions. A flat
    /// per-tile probability — the first mockup's approach — reads as visual noise.
    static func grassTile(x: Int, y: Int) -> Int {
        let clump = StableHash.pick(100, Int((Double(x) / 4).rounded(.down)),
                                         Int((Double(y) / 3).rounded(.down)), 0xA1)
        let local = StableHash.pick(100, x, y, 0xB2)
        if clump < 24 && local < 55 { return tuft }
        if clump >= 93 && local < 35 { return flowers }
        if local < 4 { return tuft }
        return plain
    }
}
