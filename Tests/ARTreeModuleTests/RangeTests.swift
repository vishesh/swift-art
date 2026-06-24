import Testing
import _CollectionsTestSupport

@testable import ARTreeModule

final class RadixTreeRangeTests: CollectionTestCase {

  // Deterministic RNG so the randomized model check is reproducible.
  private struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(_ seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
      state &+= 0x9E37_79B9_7F4A_7C15
      var z = state
      z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
      z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
      return z ^ (z >> 31)
    }
  }

  private func intTree(_ keys: [Int]) -> RadixTree<Int, Int> {
    var t = RadixTree<Int, Int>()
    for k in keys { t[k] = 2 * k }
    return t
  }

  @Test func basicIntRange() {
    let t = intTree([10, 20, 30, 40, 50])
    let r = t.entries(from: 20, to: 40)
    expectEqual(r.map { $0.key }, [20, 30, 40])
    expectEqual(r.map { $0.value }, [40, 60, 80])
  }

  @Test func boundsNotPresent() {
    let t = intTree([10, 20, 30, 40, 50])
    expectEqual(t.entries(from: 15, to: 45).map { $0.key }, [20, 30, 40])
    expectEqual(t.entries(from: 0, to: 100).map { $0.key }, [10, 20, 30, 40, 50])
    expectEqual(t.entries(from: 25, to: 25).map { $0.key }, [])  // absent singleton
    expectEqual(t.entries(from: 30, to: 30).map { $0.key }, [30])  // present singleton
  }

  @Test func emptyAndDegenerate() {
    expectEqual(intTree([]).entries(from: 0, to: 10).map { $0.key }, [])
    let t = intTree([10, 20, 30])
    expectEqual(t.entries(from: 100, to: 200).map { $0.key }, [])  // entirely above
    expectEqual(t.entries(from: -100, to: 0).map { $0.key }, [])  // entirely below
    expectEqual(t.entries(from: 40, to: 20).map { $0.key }, [])  // lower > upper
  }

  @Test func signedOrdering() {
    let t = intTree([-30, -10, 0, 10, 30])
    expectEqual(t.entries(from: -20, to: 20).map { $0.key }, [-10, 0, 10])
    expectEqual(t.entries(from: -1000, to: -1).map { $0.key }, [-30, -10])
  }

  @Test func stringRange() {
    var t = RadixTree<String, Int>()
    for (i, s) in ["apple", "apricot", "banana", "blueberry", "cherry"].enumerated() {
      t[s] = i
    }
    expectEqual(
      t.entries(from: "apq", to: "bz").map { $0.key }, ["apricot", "banana", "blueberry"])
    expectEqual(
      t.entries(from: "apple", to: "cherry").map { $0.key },
      ["apple", "apricot", "banana", "blueberry", "cherry"])
    expectEqual(t.entries(from: "d", to: "z").map { $0.key }, [])
  }

  @Test func forEachMatchesEntries() {
    let t = intTree([1, 2, 3, 5, 8, 13, 21])
    var collected: [Int] = []
    t.forEachEntry(from: 2, to: 13) { k, _ in collected.append(k) }
    expectEqual(collected, [2, 3, 5, 8, 13])
  }

  @Test func randomizedAgainstSortedModel() {
    var rng = SeededRNG(0xCAFE_BABE_F00D_1234)
    for _ in 0..<60 {
      let n = Int.random(in: 0...400, using: &rng)
      var present: Set<Int> = []
      var guard0 = 0
      while present.count < n && guard0 < 10_000 {
        present.insert(Int.random(in: -2000...2000, using: &rng))
        guard0 += 1
      }
      let keys = Array(present)
      let t = intTree(keys)
      let sorted = keys.sorted()
      for _ in 0..<15 {
        var lo = Int.random(in: -2200...2200, using: &rng)
        var hi = Int.random(in: -2200...2200, using: &rng)
        if lo > hi { swap(&lo, &hi) }
        let expected = sorted.filter { $0 >= lo && $0 <= hi }
        let got = t.entries(from: lo, to: hi).map { $0.key }
        expectEqual(got, expected)
      }
    }
  }
}
