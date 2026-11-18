/// Deterministic, seedable RNG (SplitMix64). Same seed → same maps and loot.
public struct SeededRNG: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform int in the closed range.
    public mutating func int(_ range: ClosedRange<Int>) -> Int { Int.random(in: range, using: &self) }
    /// Uniform double in [0, 1).
    public mutating func unit() -> Double { Double.random(in: 0..<1, using: &self) }
    /// True with probability p.
    public mutating func chance(_ p: Double) -> Bool { unit() < p }
}
