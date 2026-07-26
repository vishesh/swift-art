import Testing
import _CollectionsTestSupport

@testable import ARTreeModule

/// Edge cases and boundary conditions not covered by existing tests.
/// Focus on uncovering bugs at node transitions, prefix handling, and COW boundaries.
@Suite
struct ARTreeEdgeCaseTests {

  // MARK: - DeleteRange Edge Cases

  @Test
  func testDeleteRangeWithNodeTransitions() {
    // Test deleteRange when it causes multiple node type transitions
    var tree = ARTree<[UInt8]>()

    // Build Node48 (17+ children at root)
    for i in 0..<20 {
      tree.insert(key: [UInt8(i), 0], value: [UInt8(i)])
    }

    // Delete range that shrinks Node48 -> Node16
    tree.deleteRange(start: [0, 0], end: [14, 0])

    // Verify correct shrinking occurred (15 deleted, 5 remain)
    for i in 0..<15 {
      expectNil(tree.getValue(key: [UInt8(i), 0]))
    }
    for i in 15..<20 {
      expectEqual(tree.getValue(key: [UInt8(i), 0]), [UInt8(i)])
    }
  }

  @Test
  func testDeleteRangeAcrossSharedPrefixes() {
    var tree = ARTree<[UInt8]>()

    // Create tree with shared prefixes at different depths
    tree.insert(key: [1, 1, 1], value: [1])
    tree.insert(key: [1, 1, 2], value: [2])
    tree.insert(key: [1, 2, 1], value: [3])
    tree.insert(key: [1, 2, 2], value: [4])
    tree.insert(key: [2, 1, 1], value: [5])
    tree.insert(key: [2, 1, 2], value: [6])

    // Delete range that spans across prefix boundaries
    tree.deleteRange(start: [1, 1, 2], end: [2, 1, 1])

    expectEqual(tree.getValue(key: [1, 1, 1]), [1])
    expectNil(tree.getValue(key: [1, 1, 2]))
    expectNil(tree.getValue(key: [1, 2, 1]))
    expectNil(tree.getValue(key: [1, 2, 2]))
    expectNil(tree.getValue(key: [2, 1, 1]))
    expectEqual(tree.getValue(key: [2, 1, 2]), [6])
  }

  @Test
  func testDeleteRangeWithEmptyRange() {
    var tree = ARTree<[UInt8]>()
    for i in 0..<10 {
      tree.insert(key: [UInt8(i)], value: [UInt8(i)])
    }

    // Delete range where start == end but key doesn't exist
    tree.deleteRange(start: [100], end: [100])

    // All keys should remain
    for i in 0..<10 {
      expectEqual(tree.getValue(key: [UInt8(i)]), [UInt8(i)])
    }
  }

  @Test
  func testDeleteRangeAfterCOW() {
    var tree1 = ARTree<[UInt8]>()
    for i in 0..<20 {
      tree1.insert(key: [UInt8(i)], value: [UInt8(i)])
    }

    let tree2 = tree1  // Create snapshot

    // Delete range in tree1
    tree1.deleteRange(start: [5], end: [14])

    // tree1 should have deletions
    for i in 5...14 {
      expectNil(tree1.getValue(key: [UInt8(i)]))
    }

    // tree2 should be unchanged
    for i in 0..<20 {
      expectEqual(tree2.getValue(key: [UInt8(i)]), [UInt8(i)])
    }
  }

  @Test
  func testDeleteRangeEntireSubtree() {
    var tree = ARTree<[UInt8]>()

    // Build tree where entire subtree matches range
    for i in 0..<10 {
      tree.insert(key: [1, UInt8(i)], value: [UInt8(i)])
      tree.insert(key: [2, UInt8(i)], value: [UInt8(i + 100)])
    }

    // Delete entire [1, *] subtree
    tree.deleteRange(start: [1, 0], end: [1, 255])

    // Verify [1, *] gone but [2, *] intact
    for i in 0..<10 {
      expectNil(tree.getValue(key: [1, UInt8(i)]))
      expectEqual(tree.getValue(key: [2, UInt8(i)]), [UInt8(i + 100)])
    }
  }

  // MARK: - Prefix Scan Edge Cases

  @Test
  func testPrefixScanWithPartialNodePrefix() {
    var tree = ARTree<[UInt8]>()

    // Create compressed prefix in node
    tree.insert(key: [1, 2, 3, 4, 5, 6], value: [1])
    tree.insert(key: [1, 2, 3, 4, 5, 7], value: [2])
    tree.insert(key: [1, 2, 3, 9, 9, 9], value: [3])

    // Scan with prefix that matches partial node prefix exactly
    var count = 0
    let prefix: [UInt8] = [1, 2, 3, 4, 5]
    prefix.withUnsafeBufferPointer { buffer in
      let rawBuffer = UnsafeRawBufferPointer(buffer)
      tree.forEachWithPrefix(rawBuffer) { _, _ in
        count += 1
      }
    }

    expectEqual(count, 2)
  }

  @Test
  func testPrefixScanNonexistentPrefix() {
    var tree = ARTree<[UInt8]>()

    tree.insert(key: [1, 2, 3], value: [1])
    tree.insert(key: [1, 2, 4], value: [2])
    tree.insert(key: [2, 3, 4], value: [3])

    // Search for prefix with no matches
    var count = 0
    let prefix: [UInt8] = [9, 9, 9]
    prefix.withUnsafeBufferPointer { buffer in
      let rawBuffer = UnsafeRawBufferPointer(buffer)
      tree.forEachWithPrefix(rawBuffer) { _, _ in
        count += 1
      }
    }

    expectEqual(count, 0)
  }

  @Test
  func testPrefixScanLongerThanAnyKey() {
    var tree = ARTree<[UInt8]>()

    tree.insert(key: [1, 2], value: [1])
    tree.insert(key: [1, 3], value: [2])

    // Prefix longer than any key
    var count = 0
    let prefix: [UInt8] = [1, 2, 3, 4, 5]
    prefix.withUnsafeBufferPointer { buffer in
      let rawBuffer = UnsafeRawBufferPointer(buffer)
      tree.forEachWithPrefix(rawBuffer) { _, _ in
        count += 1
      }
    }

    expectEqual(count, 0)
  }

  @Test
  func testPrefixScanAfterNodeSplit() {
    var tree = ARTree<[UInt8]>()

    // Insert key with long prefix
    let commonPrefix: [UInt8] = [1, 2, 3, 4, 5]
    tree.insert(key: commonPrefix + [6], value: [1])

    // Insert another key that forces prefix split
    tree.insert(key: [1, 2, 3, 9], value: [2])

    // Scan for original prefix
    var collected: [[UInt8]] = []
    commonPrefix.withUnsafeBufferPointer { buffer in
      let rawBuffer = UnsafeRawBufferPointer(buffer)
      tree.forEachWithPrefix(rawBuffer) { key, _ in
        collected.append(Array(key))
      }
    }

    expectEqual(collected.count, 1)
    expectEqual(collected[0], commonPrefix + [6])
  }

  @Test
  func testPrefixScanAcrossNode256() {
    var tree = ARTree<[UInt8]>()

    // Create Node256 at root
    for i in 0..<256 {
      tree.insert(key: [10, UInt8(i)], value: [UInt8(i)])
    }

    // Scan with prefix that leads into Node256
    var count = 0
    let prefix: [UInt8] = [10]
    prefix.withUnsafeBufferPointer { buffer in
      let rawBuffer = UnsafeRawBufferPointer(buffer)
      tree.forEachWithPrefix(rawBuffer) { _, _ in
        count += 1
      }
    }

    expectEqual(count, 256)
  }

  @Test
  func testPrefixScanDivergingKeys() {
    var tree = ARTree<[UInt8]>()

    // Insert keys that diverge at different depths
    tree.insert(key: [1, 2, 10], value: [1])
    tree.insert(key: [1, 2, 20], value: [2])
    tree.insert(key: [1, 3, 10], value: [3])

    // Search for prefix [1, 2] - should match first two
    var count = 0
    let prefix: [UInt8] = [1, 2]
    prefix.withUnsafeBufferPointer { buffer in
      let rawBuffer = UnsafeRawBufferPointer(buffer)
      tree.forEachWithPrefix(rawBuffer) { _, _ in
        count += 1
      }
    }

    expectEqual(count, 2)
  }

  // MARK: - Node Transition Boundary Tests

  @Test
  func testNode4ToNode16TransitionBoundary() {
    var tree = ARTree<[UInt8]>()

    // Fill exactly to Node4 capacity (4 children)
    for i in 0..<4 {
      tree.insert(key: [UInt8(i)], value: [UInt8(i)])
      expectEqual(tree._root?.type, .node4)
    }

    // One more triggers Node4 -> Node16
    tree.insert(key: [4], value: [4])
    expectEqual(tree._root?.type, .node16)

    // Verify all data intact
    for i in 0..<5 {
      expectEqual(tree.getValue(key: [UInt8(i)]), [UInt8(i)])
    }

    // Delete down to 3 keys to trigger shrink back
    tree.delete(key: [4])
    tree.delete(key: [3])

    for i in 0..<3 {
      expectEqual(tree.getValue(key: [UInt8(i)]), [UInt8(i)])
    }
  }

  @Test
  func testNode16ToNode48TransitionBoundary() {
    var tree = ARTree<[UInt8]>()

    // Fill to Node16 capacity (16 children)
    for i in 0..<16 {
      tree.insert(key: [UInt8(i)], value: [UInt8(i)])
      if i < 4 {
        expectEqual(tree._root?.type, .node4)
      } else {
        expectEqual(tree._root?.type, .node16)
      }
    }

    // Trigger Node16 -> Node48
    tree.insert(key: [16], value: [16])
    expectEqual(tree._root?.type, .node48)

    // Verify all data
    for i in 0...16 {
      expectEqual(tree.getValue(key: [UInt8(i)]), [UInt8(i)])
    }
  }

  @Test
  func testNode48ToNode256TransitionBoundary() {
    var tree = ARTree<[UInt8]>()

    // Fill to Node48 capacity (48 children)
    for i in 0..<48 {
      tree.insert(key: [UInt8(i)], value: [UInt8(i)])
    }
    expectEqual(tree._root?.type, .node48)

    // Trigger Node48 -> Node256
    tree.insert(key: [48], value: [48])
    expectEqual(tree._root?.type, .node256)

    // Verify all data
    for i in 0...48 {
      expectEqual(tree.getValue(key: [UInt8(i)]), [UInt8(i)])
    }
  }

  @Test
  func testMultipleNodeTransitionsDuringDelete() {
    var tree = ARTree<[UInt8]>()

    // Build to Node48
    for i in 0..<20 {
      tree.insert(key: [UInt8(i)], value: [UInt8(i)])
    }
    expectEqual(tree._root?.type, .node48)

    // Delete down through transitions: Node48 -> Node16 -> Node4
    for i in 0..<17 {
      tree.delete(key: [UInt8(i)])
    }

    // Should be Node4 with 3 children
    expectEqual(tree._root?.type, .node4)

    for i in 17..<20 {
      expectEqual(tree.getValue(key: [UInt8(i)]), [UInt8(i)])
    }
  }

  // MARK: - COW with DeleteRange and PrefixScan

  @Test
  func testCOWDeleteRangeDoesNotAffectSnapshot() {
    var tree1 = ARTree<[UInt8]>()
    for i in 0..<30 {
      tree1.insert(key: [UInt8(i)], value: [UInt8(i)])
    }

    let snapshot = tree1

    // Modify tree1 with deleteRange
    tree1.deleteRange(start: [10], end: [19])

    // Insert new keys to tree1
    tree1.insert(key: [100], value: [100])

    // Snapshot should be completely intact
    for i in 0..<30 {
      expectEqual(snapshot.getValue(key: [UInt8(i)]), [UInt8(i)])
    }
    expectNil(snapshot.getValue(key: [100]))

    // tree1 should have changes
    for i in 10...19 {
      expectNil(tree1.getValue(key: [UInt8(i)]))
    }
    expectEqual(tree1.getValue(key: [100]), [100])
  }

  @Test
  func testCOWPrefixScanIndependent() {
    var tree1 = ARTree<[UInt8]>()
    for i in 0..<10 {
      tree1.insert(key: [1, UInt8(i)], value: [UInt8(i)])
    }

    let tree2 = tree1

    // Modify tree1
    tree1.insert(key: [1, 100], value: [100])
    tree1.delete(key: [1, 5])

    // Scan tree1
    var count1 = 0
    let prefix: [UInt8] = [1]
    prefix.withUnsafeBufferPointer { buffer in
      let rawBuffer = UnsafeRawBufferPointer(buffer)
      tree1.forEachWithPrefix(rawBuffer) { _, _ in
        count1 += 1
      }
    }
    expectEqual(count1, 10)  // 10 original - 1 deleted + 1 added

    // Scan tree2 (should be unchanged)
    var count2 = 0
    prefix.withUnsafeBufferPointer { buffer in
      let rawBuffer = UnsafeRawBufferPointer(buffer)
      tree2.forEachWithPrefix(rawBuffer) { _, _ in
        count2 += 1
      }
    }
    expectEqual(count2, 10)  // Original 10
  }

  // MARK: - Iteration Order Tests

  @Test
  func testIterationOrderAfterDeleteRange() {
    var tree = ARTree<[UInt8]>()

    // Insert in non-sorted order
    let keys: [UInt8] = [5, 1, 8, 3, 9, 2, 7, 4, 6]
    for k in keys {
      tree.insert(key: [k], value: [k])
    }

    // Delete middle range
    tree.deleteRange(start: [4], end: [6])

    // Iterate and verify sorted order excluding deleted range
    var iterated: [[UInt8]] = []
    for (key, _) in tree {
      iterated.append(key)
    }

    let expected: [[UInt8]] = [[1], [2], [3], [7], [8], [9]]
    expectEqual(iterated, expected)
  }

  @Test
  func testIterationOrderWithPrefixScan() {
    var tree = ARTree<[UInt8]>()

    // Insert with shared prefix in unsorted order
    tree.insert(key: [1, 5], value: [1])
    tree.insert(key: [1, 2], value: [2])
    tree.insert(key: [1, 8], value: [3])
    tree.insert(key: [1, 1], value: [4])
    tree.insert(key: [2, 5], value: [5])

    // Scan prefix [1] and verify sorted order
    var collected: [[UInt8]] = []
    let prefix: [UInt8] = [1]
    prefix.withUnsafeBufferPointer { buffer in
      let rawBuffer = UnsafeRawBufferPointer(buffer)
      tree.forEachWithPrefix(rawBuffer) { key, _ in
        collected.append(Array(key))
      }
    }

    let expected: [[UInt8]] = [[1, 1], [1, 2], [1, 5], [1, 8]]
    expectEqual(collected, expected)
  }

  // MARK: - Large Key Tests

  @Test
  func testDeleteRangeWithLongKeys() {
    var tree = ARTree<[UInt8]>()

    // Insert keys with long shared prefixes
    let basePrefix: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    for i in 0..<20 {
      var key = basePrefix
      key.append(UInt8(i))
      tree.insert(key: key, value: [UInt8(i)])
    }

    // Delete range in middle
    var startKey = basePrefix
    startKey.append(5)
    var endKey = basePrefix
    endKey.append(14)

    tree.deleteRange(start: startKey, end: endKey)

    // Verify deletions
    for i in 5...14 {
      var key = basePrefix
      key.append(UInt8(i))
      expectNil(tree.getValue(key: key))
    }

    // Verify survivors
    for i in [0, 1, 2, 3, 4, 15, 16, 17, 18, 19] {
      var key = basePrefix
      key.append(UInt8(i))
      expectEqual(tree.getValue(key: key), [UInt8(i)])
    }
  }

  @Test
  func testPrefixScanWithLongPrefix() {
    var tree = ARTree<[UInt8]>()

    let longPrefix: [UInt8] = Array(1..<20)

    // Insert keys with and without long prefix. The distractor must be prefix-free
    // w.r.t. the others (keys where one is a prefix of another are unsupported), so
    // start it with a byte the shared prefix never uses.
    tree.insert(key: longPrefix + [1], value: [1])
    tree.insert(key: longPrefix + [2], value: [2])
    tree.insert(key: [200, 1, 1], value: [99])  // Different prefix

    var count = 0
    longPrefix.withUnsafeBufferPointer { buffer in
      let rawBuffer = UnsafeRawBufferPointer(buffer)
      tree.forEachWithPrefix(rawBuffer) { _, _ in
        count += 1
      }
    }

    expectEqual(count, 2)
  }

  // MARK: - Single Key Edge Cases

  @Test
  func testDeleteRangeSingleKeyTree() {
    var tree = ARTree<[UInt8]>()
    tree.insert(key: [5], value: [5])

    // Delete range that includes the key
    tree.deleteRange(start: [0], end: [10])

    expectEqual(tree._root, nil)
  }

  @Test
  func testDeleteRangeSingleKeyDoesNotMatch() {
    var tree = ARTree<[UInt8]>()
    tree.insert(key: [5], value: [5])

    // Delete range that excludes the key
    tree.deleteRange(start: [10], end: [20])

    expectEqual(tree.getValue(key: [5]), [5])
  }

  @Test
  func testPrefixScanSingleKeyMatch() {
    var tree = ARTree<[UInt8]>()
    tree.insert(key: [1, 2, 3], value: [99])

    var count = 0
    let prefix: [UInt8] = [1, 2]
    prefix.withUnsafeBufferPointer { buffer in
      let rawBuffer = UnsafeRawBufferPointer(buffer)
      tree.forEachWithPrefix(rawBuffer) { _, _ in
        count += 1
      }
    }

    expectEqual(count, 1)
  }

  // MARK: - Boundary Byte Values

  @Test
  func testDeleteRangeWithZeroAndMaxBytes() {
    var tree = ARTree<[UInt8]>()

    tree.insert(key: [0, 0], value: [1])
    tree.insert(key: [0, 255], value: [2])
    tree.insert(key: [255, 0], value: [3])
    tree.insert(key: [255, 255], value: [4])
    tree.insert(key: [128, 128], value: [5])

    // Delete from min to middle
    tree.deleteRange(start: [0, 0], end: [128, 128])

    expectNil(tree.getValue(key: [0, 0]))
    expectNil(tree.getValue(key: [0, 255]))
    expectNil(tree.getValue(key: [128, 128]))
    expectEqual(tree.getValue(key: [255, 0]), [3])
    expectEqual(tree.getValue(key: [255, 255]), [4])
  }

  @Test
  func testPrefixScanWithZeroByte() {
    var tree = ARTree<[UInt8]>()

    tree.insert(key: [0, 1], value: [1])
    tree.insert(key: [0, 2], value: [2])
    tree.insert(key: [1, 1], value: [3])

    var count = 0
    let prefix: [UInt8] = [0]
    prefix.withUnsafeBufferPointer { buffer in
      let rawBuffer = UnsafeRawBufferPointer(buffer)
      tree.forEachWithPrefix(rawBuffer) { _, _ in
        count += 1
      }
    }

    expectEqual(count, 2)
  }

  @Test
  func testPrefixScanWithMaxByte() {
    var tree = ARTree<[UInt8]>()

    tree.insert(key: [255, 1], value: [1])
    tree.insert(key: [255, 2], value: [2])
    tree.insert(key: [254, 1], value: [3])

    var count = 0
    let prefix: [UInt8] = [255]
    prefix.withUnsafeBufferPointer { buffer in
      let rawBuffer = UnsafeRawBufferPointer(buffer)
      tree.forEachWithPrefix(rawBuffer) { _, _ in
        count += 1
      }
    }

    expectEqual(count, 2)
  }
}

/// Tests combining deleteRange and prefixScan operations
@Suite
struct ARTreeCombinedOperationsTests {

  @Test
  func testPrefixScanAfterDeleteRange() {
    var tree = ARTree<[UInt8]>()

    for i in 0..<20 {
      tree.insert(key: [1, UInt8(i)], value: [UInt8(i)])
    }

    // Delete middle range
    tree.deleteRange(start: [1, 5], end: [1, 14])

    // Scan remaining keys with prefix [1]
    var collected: [[UInt8]] = []
    let prefix: [UInt8] = [1]
    prefix.withUnsafeBufferPointer { buffer in
      let rawBuffer = UnsafeRawBufferPointer(buffer)
      tree.forEachWithPrefix(rawBuffer) { key, _ in
        collected.append(Array(key))
      }
    }

    expectEqual(collected.count, 10)  // 0-4 and 15-19

    // Verify order
    expectEqual(collected[0], [1, 0])
    expectEqual(collected[4], [1, 4])
    expectEqual(collected[5], [1, 15])
    expectEqual(collected[9], [1, 19])
  }

  @Test
  func testDeleteRangeOfPrefixScanResults() {
    var tree = ARTree<[UInt8]>()

    // Build tree with multiple prefixes
    for i in 0..<10 {
      tree.insert(key: [1, UInt8(i)], value: [UInt8(i)])
      tree.insert(key: [2, UInt8(i)], value: [UInt8(i + 100)])
    }

    // Scan to identify [1, *] keys
    var toDelete: [[UInt8]] = []
    let prefix: [UInt8] = [1]
    prefix.withUnsafeBufferPointer { buffer in
      let rawBuffer = UnsafeRawBufferPointer(buffer)
      tree.forEachWithPrefix(rawBuffer) { key, _ in
        toDelete.append(Array(key))
      }
    }

    expectEqual(toDelete.count, 10)

    // Now delete range covering those keys
    tree.deleteRange(start: [1, 0], end: [1, 9])

    // Verify [1, *] gone
    for i in 0..<10 {
      expectNil(tree.getValue(key: [1, UInt8(i)]))
    }

    // Verify [2, *] intact
    for i in 0..<10 {
      expectEqual(tree.getValue(key: [2, UInt8(i)]), [UInt8(i + 100)])
    }
  }

  @Test
  func testMultipleDeleteRangesWithPrefixScan() {
    var tree = ARTree<[UInt8]>()

    for i in 0..<100 {
      tree.insert(key: [UInt8(i)], value: [UInt8(i)])
    }

    // Delete multiple ranges
    tree.deleteRange(start: [10], end: [19])
    tree.deleteRange(start: [30], end: [39])
    tree.deleteRange(start: [50], end: [59])

    // Count all remaining with empty prefix (should match all)
    var count = 0
    let prefix: [UInt8] = []
    prefix.withUnsafeBufferPointer { buffer in
      let rawBuffer = UnsafeRawBufferPointer(buffer)
      tree.forEachWithPrefix(rawBuffer) { _, _ in
        count += 1
      }
    }

    expectEqual(count, 70)  // 100 - 30 deleted
  }
}

/// Tests for stress scenarios that could expose memory issues
@Suite
struct ARTreeStressEdgeCaseTests {

  @Test
  func testAlternatingDeleteRangeAndInsert() {
    var tree = ARTree<[UInt8]>()

    // Build initial tree
    for i in 0..<50 {
      tree.insert(key: [UInt8(i)], value: [UInt8(i)])
    }

    // Alternate delete ranges and inserts
    tree.deleteRange(start: [10], end: [19])
    tree.insert(key: [100], value: [100])

    tree.deleteRange(start: [30], end: [39])
    tree.insert(key: [101], value: [101])

    tree.deleteRange(start: [0], end: [4])
    tree.insert(key: [102], value: [102])

    // Verify final state
    var remaining = 0
    for (_, _) in tree {
      remaining += 1
    }

    expectEqual(remaining, 50 - 25 + 3)  // 50 - (10+10+5) + 3 new
  }

  @Test
  func testPrefixScanDuringNodeRestructuring() {
    var tree = ARTree<[UInt8]>()

    // Build Node16
    for i in 0..<10 {
      tree.insert(key: [1, UInt8(i)], value: [UInt8(i)])
    }

    // Take snapshot
    let snapshot = tree

    // Grow tree1 to Node48
    for i in 10..<20 {
      tree.insert(key: [1, UInt8(i)], value: [UInt8(i)])
    }

    // Scan both trees
    var count1 = 0
    var count2 = 0
    let prefix: [UInt8] = [1]

    prefix.withUnsafeBufferPointer { buffer in
      let rawBuffer = UnsafeRawBufferPointer(buffer)
      tree.forEachWithPrefix(rawBuffer) { _, _ in
        count1 += 1
      }
    }

    prefix.withUnsafeBufferPointer { buffer in
      let rawBuffer = UnsafeRawBufferPointer(buffer)
      snapshot.forEachWithPrefix(rawBuffer) { _, _ in
        count2 += 1
      }
    }

    expectEqual(count1, 20)
    expectEqual(count2, 10)
  }

  @Test
  func testDeleteRangeWithInterleavedKeys() {
    var tree = ARTree<[UInt8]>()

    // Insert keys in interleaved pattern
    for i in 0..<100 {
      if i % 2 == 0 {
        tree.insert(key: [1, UInt8(i)], value: [UInt8(i)])
      } else {
        tree.insert(key: [2, UInt8(i)], value: [UInt8(i)])
      }
    }

    // Delete range that spans both prefixes
    tree.deleteRange(start: [1, 50], end: [2, 50])

    // Count survivors in each prefix
    var count1 = 0
    var count2 = 0

    let prefix1: [UInt8] = [1]
    prefix1.withUnsafeBufferPointer { buffer in
      let rawBuffer = UnsafeRawBufferPointer(buffer)
      tree.forEachWithPrefix(rawBuffer) { _, _ in
        count1 += 1
      }
    }

    let prefix2: [UInt8] = [2]
    prefix2.withUnsafeBufferPointer { buffer in
      let rawBuffer = UnsafeRawBufferPointer(buffer)
      tree.forEachWithPrefix(rawBuffer) { _, _ in
        count2 += 1
      }
    }

    // Should have deleted [1,50+] and [2,0-50]
    expectTrue(count1 < 50)
    expectTrue(count2 < 50)
  }
}
