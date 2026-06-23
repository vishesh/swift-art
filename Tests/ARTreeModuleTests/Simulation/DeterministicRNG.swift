// A self-contained SplitMix64 generator.
//
// We deliberately do NOT use `_CollectionsTestSupport.RepeatableRandomNumberGenerator`:
// its `globalSeed` is `42.hashValue`, and `Int.hashValue` is randomized per process,
// so its sequence is not reproducible across runs. This generator is seeded purely
// from the given `UInt64`, so `(seed) -> sequence` is stable everywhere — which is the
// whole point of deterministic simulation testing.
struct SplitMix64: RandomNumberGenerator {
  private var state: UInt64

  init(seed: UInt64) { self.state = seed }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}
