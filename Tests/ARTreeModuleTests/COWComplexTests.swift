import Testing
@testable import ARTreeModule
import _CollectionsTestSupport

/// Complex Copy-on-Write scenarios that test reference management,
/// shared structure handling, and mutation isolation.
@Suite
struct COWComplexTests {

  // MARK: - Multi-level Snapshot Trees

  @Test
  func testThreeLevelSnapshotChain() {
    var tree1 = ARTree<[UInt8]>()

    // Build base
    for i in 0..<10 {
      tree1.insert(key: [UInt8(i)], value: [UInt8(i)])
    }

    var tree2 = tree1  // First snapshot

    // Modify tree1
    tree1.insert(key: [100], value: [100])
    tree1.delete(key: [5])

    var tree3 = tree1  // Second snapshot from modified tree1

    // Modify tree1 again
    tree1.insert(key: [101], value: [101])
    tree1.delete(key: [6])

    // Modify tree2
    tree2.insert(key: [200], value: [200])
    tree2.delete(key: [7])

    // Modify tree3
    tree3.insert(key: [50], value: [50])
    tree3.delete(key: [8])

    // Verify all trees independent
    // tree1: original - [5,6] + [100, 101]
    expectNil(tree1.getValue(key: [5]))
    expectNil(tree1.getValue(key: [6]))
    expectEqual(tree1.getValue(key: [100]), [100])
    expectEqual(tree1.getValue(key: [101]), [101])
    expectNil(tree1.getValue(key: [200]))
    expectNil(tree1.getValue(key: [50]))

    // tree2: original - [7] + [200]
    expectEqual(tree2.getValue(key: [5]), [5])
    expectEqual(tree2.getValue(key: [6]), [6])
    expectNil(tree2.getValue(key: [7]))
    expectEqual(tree2.getValue(key: [200]), [200])
    expectNil(tree2.getValue(key: [100]))
    expectNil(tree2.getValue(key: [50]))

    // tree3: original - [5] + [100] - [8] + [50]
    expectNil(tree3.getValue(key: [5]))
    expectEqual(tree3.getValue(key: [6]), [6])
    expectNil(tree3.getValue(key: [8]))
    expectEqual(tree3.getValue(key: [100]), [100])
    expectEqual(tree3.getValue(key: [50]), [50])
    expectNil(tree3.getValue(key: [101]))
    expectNil(tree3.getValue(key: [200]))
  }

  @Test
  func testSnapshotForestWithSharedSubtrees() {
    var base = ARTree<[UInt8]>()

    // Build tree with distinct subtrees
    for i in 0..<5 {
      base.insert(key: [1, UInt8(i)], value: [UInt8(i)])
      base.insert(key: [2, UInt8(i)], value: [UInt8(i + 100)])
    }

    var snap1 = base
    var snap2 = base

    // Modify snap1's [1, *] subtree
    snap1.insert(key: [1, 10], value: [10])
    snap1.delete(key: [1, 0])

    // Modify snap2's [2, *] subtree
    snap2.insert(key: [2, 10], value: [110])
    snap2.delete(key: [2, 0])

    // Verify base unchanged
    expectEqual(base.getValue(key: [1, 0]), [0])
    expectEqual(base.getValue(key: [2, 0]), [100])
    expectNil(base.getValue(key: [1, 10]))
    expectNil(base.getValue(key: [2, 10]))

    // Verify snap1 has modified [1, *], original [2, *]
    expectNil(snap1.getValue(key: [1, 0]))
    expectEqual(snap1.getValue(key: [1, 10]), [10])
    expectEqual(snap1.getValue(key: [2, 0]), [100])
    expectNil(snap1.getValue(key: [2, 10]))

    // Verify snap2 has original [1, *], modified [2, *]
    expectEqual(snap2.getValue(key: [1, 0]), [0])
    expectNil(snap2.getValue(key: [1, 10]))
    expectNil(snap2.getValue(key: [2, 0]))
    expectEqual(snap2.getValue(key: [2, 10]), [110])
  }

  @Test
  func testDeepSnapshotNesting() {
    var trees: [ARTree<[UInt8]>] = []
    var current = ARTree<[UInt8]>()

    // Create 10 snapshots, each modified from previous
    for round in 0..<10 {
      current.insert(key: [UInt8(round)], value: [UInt8(round)])
      trees.append(current)
    }

    // Verify each snapshot has exactly its expected keys
    for (idx, tree) in trees.enumerated() {
      var count = 0
      for (key, value) in tree {
        expectTrue(key[0] <= UInt8(idx))
        expectEqual(key[0], value[0])
        count += 1
      }
      expectEqual(count, idx + 1)
    }
  }

  // MARK: - COW with DeleteRange

  @Test
  func testDeleteRangeWithMultipleSnapshots() {
    var tree1 = ARTree<[UInt8]>()

    for i in 0..<50 {
      tree1.insert(key: [UInt8(i)], value: [UInt8(i)])
    }

    let snap1 = tree1
    let snap2 = tree1

    // Delete different ranges in each
    tree1.deleteRange(start: [0], end: [9])

    var tree2 = snap1
    tree2.deleteRange(start: [10], end: [19])

    var tree3 = snap2
    tree3.deleteRange(start: [20], end: [29])

    // Verify each has different deletions
    // tree1: deleted [0-9]
    for i in 0...9 {
      expectNil(tree1.getValue(key: [UInt8(i)]))
    }
    for i in 10..<50 {
      expectEqual(tree1.getValue(key: [UInt8(i)]), [UInt8(i)])
    }

    // tree2: deleted [10-19]
    for i in 0...9 {
      expectEqual(tree2.getValue(key: [UInt8(i)]), [UInt8(i)])
    }
    for i in 10...19 {
      expectNil(tree2.getValue(key: [UInt8(i)]))
    }
    for i in 20..<50 {
      expectEqual(tree2.getValue(key: [UInt8(i)]), [UInt8(i)])
    }

    // tree3: deleted [20-29]
    for i in 0...19 {
      expectEqual(tree3.getValue(key: [UInt8(i)]), [UInt8(i)])
    }
    for i in 20...29 {
      expectNil(tree3.getValue(key: [UInt8(i)]))
    }
    for i in 30..<50 {
      expectEqual(tree3.getValue(key: [UInt8(i)]), [UInt8(i)])
    }

    // Original snapshots unchanged
    for i in 0..<50 {
      expectEqual(snap1.getValue(key: [UInt8(i)]), [UInt8(i)])
      expectEqual(snap2.getValue(key: [UInt8(i)]), [UInt8(i)])
    }
  }

  @Test
  func testDeleteRangeOnSharedDeepSubtree() {
    var tree1 = ARTree<[UInt8]>()

    // Build deep structure
    for i in 0..<10 {
      tree1.insert(key: [1, 2, 3, UInt8(i)], value: [UInt8(i)])
    }

    let tree2 = tree1

    // Delete range in tree1's deep subtree
    tree1.deleteRange(start: [1, 2, 3, 3], end: [1, 2, 3, 7])

    // Verify tree2 unaffected
    for i in 0..<10 {
      expectEqual(tree2.getValue(key: [1, 2, 3, UInt8(i)]), [UInt8(i)])
    }

    // Verify tree1 deletions
    for i in 3...7 {
      expectNil(tree1.getValue(key: [1, 2, 3, UInt8(i)]))
    }
    for i in [0, 1, 2, 8, 9] {
      expectEqual(tree1.getValue(key: [1, 2, 3, UInt8(i)]), [UInt8(i)])
    }
  }

  // MARK: - COW with Prefix Scan

  @Test
  func testPrefixScanOnSnapshotWhileModifyingOriginal() {
    var tree1 = ARTree<[UInt8]>()

    for i in 0..<20 {
      tree1.insert(key: [1, UInt8(i)], value: [UInt8(i)])
    }

    let snapshot = tree1

    // Modify tree1
    tree1.insert(key: [1, 100], value: [100])
    tree1.delete(key: [1, 10])

    // Scan both
    var count1 = 0, count2 = 0
    let prefix: [UInt8] = [1]

    prefix.withUnsafeBufferPointer { buffer in
      let rawBuffer = UnsafeRawBufferPointer(buffer)
      tree1.forEachWithPrefix(rawBuffer) { _, _ in
        count1 += 1
      }
    }

    prefix.withUnsafeBufferPointer { buffer in
      let rawBuffer = UnsafeRawBufferPointer(buffer)
      snapshot.forEachWithPrefix(rawBuffer) { _, _ in
        count2 += 1
      }
    }

    expectEqual(count1, 20)  // 20 - 1 + 1
    expectEqual(count2, 20)  // Original 20
  }

  @Test
  func testPrefixScanOnMultipleSnapshotsWithDivergentPrefixes() {
    var base = ARTree<[UInt8]>()

    // Insert keys with prefixes [1, *] and [2, *]
    for i in 0..<10 {
      base.insert(key: [1, UInt8(i)], value: [UInt8(i)])
      base.insert(key: [2, UInt8(i)], value: [UInt8(i + 100)])
    }

    var snap1 = base
    var snap2 = base

    // Modify different prefixes
    snap1.insert(key: [1, 100], value: [100])
    snap2.insert(key: [2, 100], value: [200])

    // Scan [1, *] in each
    var base1 = 0, snap1_1 = 0, snap2_1 = 0
    let prefix1: [UInt8] = [1]

    prefix1.withUnsafeBufferPointer { buffer in
      let rawBuffer = UnsafeRawBufferPointer(buffer)
      base.forEachWithPrefix(rawBuffer) { _, _ in base1 += 1 }
      snap1.forEachWithPrefix(rawBuffer) { _, _ in snap1_1 += 1 }
      snap2.forEachWithPrefix(rawBuffer) { _, _ in snap2_1 += 1 }
    }

    expectEqual(base1, 10)
    expectEqual(snap1_1, 11)
    expectEqual(snap2_1, 10)

    // Scan [2, *] in each
    var base2 = 0, snap1_2 = 0, snap2_2 = 0
    let prefix2: [UInt8] = [2]

    prefix2.withUnsafeBufferPointer { buffer in
      let rawBuffer = UnsafeRawBufferPointer(buffer)
      base.forEachWithPrefix(rawBuffer) { _, _ in base2 += 1 }
      snap1.forEachWithPrefix(rawBuffer) { _, _ in snap1_2 += 1 }
      snap2.forEachWithPrefix(rawBuffer) { _, _ in snap2_2 += 1 }
    }

    expectEqual(base2, 10)
    expectEqual(snap1_2, 10)
    expectEqual(snap2_2, 11)
  }

  // MARK: - COW Edge Cases

  @Test
  func testReplacingValueInSnapshot() {
    var tree1 = ARTree<[UInt8]>()

    tree1.insert(key: [1, 2, 3], value: [100])

    var tree2 = tree1

    // Replace value in tree2
    tree2.insert(key: [1, 2, 3], value: [200])

    // Verify independence
    expectEqual(tree1.getValue(key: [1, 2, 3]), [100])
    expectEqual(tree2.getValue(key: [1, 2, 3]), [200])
  }

  @Test
  func testReplacingValueMultipleTimes() {
    var tree1 = ARTree<[UInt8]>()

    tree1.insert(key: [1], value: [1])
    let snap1 = tree1

    tree1.insert(key: [1], value: [2])
    let snap2 = tree1

    tree1.insert(key: [1], value: [3])
    let snap3 = tree1

    tree1.insert(key: [1], value: [4])

    // Each snapshot should have its value
    expectEqual(snap1.getValue(key: [1]), [1])
    expectEqual(snap2.getValue(key: [1]), [2])
    expectEqual(snap3.getValue(key: [1]), [3])
    expectEqual(tree1.getValue(key: [1]), [4])
  }

  @Test
  func testSnapshotAfterDeleteToEmpty() {
    var tree1 = ARTree<[UInt8]>()

    tree1.insert(key: [1], value: [1])
    tree1.insert(key: [2], value: [2])

    let snap1 = tree1

    tree1.delete(key: [1])
    tree1.delete(key: [2])

    // tree1 should be empty
    expectEqual(tree1._root, nil)

    // snap1 should have both keys
    expectEqual(snap1.getValue(key: [1]), [1])
    expectEqual(snap1.getValue(key: [2]), [2])

    // Insert into empty tree1
    tree1.insert(key: [3], value: [3])

    expectEqual(tree1.getValue(key: [3]), [3])
    expectNil(snap1.getValue(key: [3]))
  }

  @Test
  func testCOWWithNodeCollapse() {
    var tree1 = ARTree<[UInt8]>()

    // Create structure that will collapse
    tree1.insert(key: [1, 2, 3], value: [1])
    tree1.insert(key: [1, 2, 4], value: [2])
    tree1.insert(key: [1, 5, 6], value: [3])

    let snap = tree1

    // Delete in tree1 to trigger collapse
    tree1.delete(key: [1, 2, 3])

    // Verify snap unaffected
    expectEqual(snap.getValue(key: [1, 2, 3]), [1])
    expectEqual(snap.getValue(key: [1, 2, 4]), [2])
    expectEqual(snap.getValue(key: [1, 5, 6]), [3])

    // Verify tree1 changed
    expectNil(tree1.getValue(key: [1, 2, 3]))
    expectEqual(tree1.getValue(key: [1, 2, 4]), [2])
    expectEqual(tree1.getValue(key: [1, 5, 6]), [3])
  }

  // MARK: - Iteration with COW

  @Test
  func testIterationIndependenceAfterCOW() {
    var tree1 = ARTree<[UInt8]>()

    for i in 0..<20 {
      tree1.insert(key: [UInt8(i)], value: [UInt8(i)])
    }

    let tree2 = tree1

    // Modify tree1
    tree1.insert(key: [100], value: [100])
    tree1.delete(key: [10])

    // Iterate both
    var keys1: [[UInt8]] = []
    var keys2: [[UInt8]] = []

    for (k, _) in tree1 {
      keys1.append(k)
    }

    for (k, _) in tree2 {
      keys2.append(k)
    }

    expectEqual(keys1.count, 20)  // 20 - 1 + 1
    expectEqual(keys2.count, 20)  // Original 20

    expectTrue(keys1.contains([100]))
    expectFalse(keys1.contains([10]))

    expectFalse(keys2.contains([100]))
    expectTrue(keys2.contains([10]))
  }

  @Test
  func testIterationDuringCOWModification() {
    var tree1 = ARTree<[UInt8]>()

    for i in 0..<30 {
      tree1.insert(key: [UInt8(i)], value: [UInt8(i)])
    }

    let tree2 = tree1

    // Collect tree1 keys before modification
    var originalKeys: [[UInt8]] = []
    for (k, _) in tree1 {
      originalKeys.append(k)
    }

    // Modify tree1
    tree1.deleteRange(start: [10], end: [19])

    // Iterate modified tree1
    var modifiedKeys: [[UInt8]] = []
    for (k, _) in tree1 {
      modifiedKeys.append(k)
    }

    // Iterate tree2
    var snap2Keys: [[UInt8]] = []
    for (k, _) in tree2 {
      snap2Keys.append(k)
    }

    expectEqual(originalKeys.count, 30)
    expectEqual(modifiedKeys.count, 20)
    expectEqual(snap2Keys.count, 30)
  }

  // MARK: - Complex Shared Structure

  @Test
  func testPartiallySharedStructureModification() {
    var tree1 = ARTree<[UInt8]>()

    // Build tree with multiple subtrees
    for i in 0..<10 {
      tree1.insert(key: [1, UInt8(i)], value: [UInt8(i)])
      tree1.insert(key: [2, UInt8(i)], value: [UInt8(i + 100)])
      tree1.insert(key: [3, UInt8(i)], value: [UInt8(i + 200)])
    }

    let tree2 = tree1

    // Modify only [2, *] subtree in tree1
    tree1.insert(key: [2, 100], value: [100])
    tree1.delete(key: [2, 5])

    // Verify [1, *] and [3, *] still shared (structural sharing)
    // We can't directly test sharing, but verify correctness

    // tree1 should have modifications only in [2, *]
    for i in 0..<10 {
      expectEqual(tree1.getValue(key: [1, UInt8(i)]), [UInt8(i)])
      expectEqual(tree1.getValue(key: [3, UInt8(i)]), [UInt8(i + 200)])
    }
    expectNil(tree1.getValue(key: [2, 5]))
    expectEqual(tree1.getValue(key: [2, 100]), [100])

    // tree2 should be unchanged
    for i in 0..<10 {
      expectEqual(tree2.getValue(key: [1, UInt8(i)]), [UInt8(i)])
      expectEqual(tree2.getValue(key: [2, UInt8(i)]), [UInt8(i + 100)])
      expectEqual(tree2.getValue(key: [3, UInt8(i)]), [UInt8(i + 200)])
    }
    expectNil(tree2.getValue(key: [2, 100]))
  }

  @Test
  func testMassiveSnapshotArray() {
    // Test that we can maintain many snapshots without leaks
    var snapshots: [ARTree<[UInt8]>] = []
    var base = ARTree<[UInt8]>()

    for i in 0..<100 {
      base.insert(key: [UInt8(i)], value: [UInt8(i)])

      // Take snapshot every 10 inserts
      if (i + 1) % 10 == 0 {
        snapshots.append(base)
      }
    }

    // Verify each snapshot
    for (idx, snap) in snapshots.enumerated() {
      var count = 0
      for _ in snap {
        count += 1
      }
      // Snapshots were taken at indices 9, 19, 29, ..., 99
      // So snapshot 0 has 10 keys, snapshot 1 has 20 keys, etc.
      expectEqual(count, (idx + 1) * 10)
    }
  }
}
