import Testing
import _CollectionsTestSupport
@testable import ARTreeModule

/// Deterministic regressions for bugs first surfaced by the simulation harness
/// (see `Simulation/`). Each pins a specific fix so it can't silently regress.
@Suite struct COWRegressionTests {
  // #1: `removeChild` leaves a stale byte at keys[count]; `addChild`'s duplicate
  // assertion must not read it on an append (slot == count).
  @Test func reinsertAfterDeleteDoesNotTrap() {
    var t = ARTree<Int>()
    for b: UInt8 in [1, 2, 3, 4, 5] { t.insert(key: [9, b, 0], value: Int(b)) }
    t.delete(key: [9, 5, 0])                  // removes the largest branch byte (left stale)
    t.insert(key: [9, 5, 7, 0], value: 99)    // re-adds branch byte 5 as an append
    expectEqual(t.getValue(key: [9, 5, 7, 0]), 99)
    for b: UInt8 in [1, 2, 3, 4] { expectEqual(t.getValue(key: [9, b, 0]), Int(b)) }
  }

  // #2: deleting a 2-key tree down to 1 key collapses the root to a bare leaf; the
  // Sequence iterator must handle a leaf root rather than trapping.
  @Test func leafRootIterates() {
    var t = ARTree<Int>()
    t.insert(key: [1, 0], value: 10)
    t.insert(key: [2, 0], value: 20)
    t.delete(key: [1, 0])
    expectEqual(t.getValue(key: [2, 0]), 20)
    expectEqualElements(Array(t).map { $0.0 }, [[2, 0]])
    t.delete(key: [2, 0])
    expectEqualElements(Array(t).map { $0.0 }, [[UInt8]]())
  }

  // #3a: delete-collapse path compression must clone the surviving child before
  // rewriting its prefix, or it corrupts copies that share that child.
  @Test func collapseMergeDoesNotCorruptCopy() {
    var a = ARTree<Int>()
    a.insert(key: [1, 1, 0], value: 1)
    a.insert(key: [1, 2, 5, 0], value: 2)
    a.insert(key: [1, 2, 6, 0], value: 3)
    var c = a
    c.delete(key: [1, 1, 0])  // root collapses; merges prefix into the shared [1,2] child
    expectEqual(a.getValue(key: [1, 1, 0]), 1)
    expectEqual(a.getValue(key: [1, 2, 5, 0]), 2)
    expectEqual(a.getValue(key: [1, 2, 6, 0]), 3)
    expectEqual(c.getValue(key: [1, 1, 0]), nil)
    expectEqual(c.getValue(key: [1, 2, 5, 0]), 2)
    expectEqual(c.getValue(key: [1, 2, 6, 0]), 3)
  }

  // #3c: the surviving sibling is off the unique mutation path, so a path-unique
  // delete can still mutate a shared sibling. Snapshot, replace, then delete the
  // sibling-adjacent key; the snapshot must be untouched. (Minimized from a seed.)
  @Test func collapseMergeDoesNotCorruptSnapshot() {
    let kA: [UInt8] = [3, 3, 5, 3, 6, 3, 2, 2, 0]
    let kMid: [UInt8] = [3, 3, 2, 6, 5, 4, 5, 4, 4, 0]
    let kB: [UInt8] = [3, 3, 5, 3, 6, 6, 6, 4, 5, 1, 4, 3, 4, 6, 0]
    var t = ARTree<Int>()
    t.insert(key: kA, value: 5)
    t.insert(key: kMid, value: 765)
    t.insert(key: kB, value: 766)
    let snap = t
    t.insert(key: kMid, value: 772)  // replace (clones the path to kMid, sharing the sibling)
    t.delete(key: kMid)              // collapse merges the shared sibling's prefix
    expectEqual(snap.getValue(key: kA), 5)
    expectEqual(snap.getValue(key: kMid), 765)
    expectEqual(snap.getValue(key: kB), 766)
    expectEqual(t.getValue(key: kA), 5)
    expectEqual(t.getValue(key: kMid), nil)
    expectEqual(t.getValue(key: kB), 766)
  }

  // #3b: growing/shrinking through Node48/Node256 while a copy is alive must not
  // leak (the conversions used to double-retain children).
  @Test func wideCopyOnWriteDoesNotLeak() {
    withLifetimeTracking { tracker in
      var t = ARTree<LifetimeTracked<Int>>()
      for b in 0..<60 { t.insert(key: [UInt8(b), 0], value: tracker.instance(for: b)) }
      let snap = t                                  // share, forcing COW clones below
      for b in 0..<60 { t.insert(key: [UInt8(b), 1], value: tracker.instance(for: 100 + b)) }
      for b in 0..<40 { t.delete(key: [UInt8(b), 0]) }   // shrink Node256 -> Node48 -> ...
      expectEqual(snap.getValue(key: [10, 0])?.payload, 10)
      expectEqual(t.getValue(key: [10, 1])?.payload, 110)
    }
  }
}
