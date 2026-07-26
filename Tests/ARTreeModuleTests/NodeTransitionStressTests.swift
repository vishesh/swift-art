import Testing
import _CollectionsTestSupport

@testable import ARTreeModule

/// Stress tests focused on node type transitions under various conditions.
/// These tests probe behavior at exact transition boundaries, with COW, and during cascading operations.
@Suite
struct NodeTransitionStressTests {

  // MARK: - Exact Boundary Transitions

  @Test
  func testNode4ToLeafTransition() {
    var tree = ARTree<[UInt8]>()

    // Create Node4 with 2 children
    tree.insert(key: [1], value: [1])
    tree.insert(key: [2], value: [2])
    expectEqual(tree._root?.type, .node4)

    // Delete one - should still be Node4
    tree.delete(key: [1])
    expectEqual(tree._root?.type, .leaf)

    // Verify remaining key
    expectEqual(tree.getValue(key: [2]), [2])
  }

  @Test
  func testRepeatedGrowthAndShrinkage() {
    var tree = ARTree<[UInt8]>()

    // Cycle: grow to Node16, shrink to Node4, repeat
    for cycle in 0..<3 {
      // Grow to Node16
      for i in 0..<5 {
        tree.insert(key: [UInt8(cycle), UInt8(i)], value: [UInt8(i)])
      }

      // Shrink back to Node4
      tree.delete(key: [UInt8(cycle), 0])

      // Verify structure
      for i in 1..<5 {
        expectEqual(tree.getValue(key: [UInt8(cycle), UInt8(i)]), [UInt8(i)])
      }
    }
  }

  @Test
  func testNode256BuildAndVerify() {
    var tree = ARTree<[UInt8]>()

    // Build Node256 (49 children)
    for i in 0..<49 {
      tree.insert(key: [UInt8(i)], value: [UInt8(i)])
    }
    expectEqual(tree._root?.type, .node256)

    // Verify all keys present
    for i in 0..<49 {
      expectEqual(tree.getValue(key: [UInt8(i)]), [UInt8(i)])
    }
  }

  @Test
  func testNode48ToNode16WithMinimalDeletion() {
    var tree = ARTree<[UInt8]>()

    // Build Node48 (17 children)
    for i in 0..<17 {
      tree.insert(key: [UInt8(i)], value: [UInt8(i)])
    }
    expectEqual(tree._root?.type, .node48)

    // Node48 shrinks to Node16 at count == 13 (hysteresis), so delete down to 13.
    for i in 0..<4 {
      tree.delete(key: [UInt8(i)])
    }
    expectEqual(tree._root?.type, .node16)

    // Verify all remaining
    for i in 4..<17 {
      expectEqual(tree.getValue(key: [UInt8(i)]), [UInt8(i)])
    }
  }

  @Test
  func testNode16VerifyAndDelete() {
    var tree = ARTree<[UInt8]>()

    // Build Node16 (5 children)
    for i in 0..<5 {
      tree.insert(key: [UInt8(i)], value: [UInt8(i)])
    }
    expectEqual(tree._root?.type, .node16)

    // Delete to reduce size
    tree.delete(key: [0])
    tree.delete(key: [1])

    // Verify remaining
    for i in 2..<5 {
      expectEqual(tree.getValue(key: [UInt8(i)]), [UInt8(i)])
    }
  }

  // MARK: - Nested Node Transitions

  @Test
  func testNestedNodeTransitionOnInsert() {
    var tree = ARTree<[UInt8]>()

    // Create structure with nested nodes at transition boundaries
    // Root Node4, child Node4
    tree.insert(key: [1, 1], value: [1])
    tree.insert(key: [1, 2], value: [2])
    tree.insert(key: [2, 1], value: [3])

    // Grow child node [1, *] to Node16
    for i in 3..<6 {
      tree.insert(key: [1, UInt8(i)], value: [UInt8(i)])
    }

    // Verify all keys accessible
    for i in 1..<6 {
      expectEqual(tree.getValue(key: [1, UInt8(i)]), [UInt8(i)])
    }
    expectEqual(tree.getValue(key: [2, 1]), [3])
  }

  @Test
  func testNestedNodeTransitionOnDelete() {
    var tree = ARTree<[UInt8]>()

    // Build nested structure with child at Node16
    for i in 0..<6 {
      tree.insert(key: [1, UInt8(i)], value: [UInt8(i)])
    }
    tree.insert(key: [2, 1], value: [99])

    // Delete child node down to Node4
    tree.delete(key: [1, 0])
    tree.delete(key: [1, 1])

    // Verify structure
    for i in 2..<6 {
      expectEqual(tree.getValue(key: [1, UInt8(i)]), [UInt8(i)])
    }
    expectEqual(tree.getValue(key: [2, 1]), [99])
  }

  @Test
  func testCascadingNodeCollapseFromLeafDelete() {
    var tree = ARTree<[UInt8]>()

    // Create deep structure that can collapse
    tree.insert(key: [1, 2, 3, 4], value: [1])
    tree.insert(key: [1, 2, 3, 5], value: [2])
    tree.insert(key: [1, 2, 6, 7], value: [3])

    // Delete one key at [1, 2, 3, *] subtree
    tree.delete(key: [1, 2, 3, 4])

    // Verify remaining keys
    expectEqual(tree.getValue(key: [1, 2, 3, 5]), [2])
    expectEqual(tree.getValue(key: [1, 2, 6, 7]), [3])
  }

  // MARK: - COW During Transitions

  @Test
  func testCOWDuringNode4ToNode16Transition() {
    var tree1 = ARTree<[UInt8]>()

    // Build to Node4 capacity
    for i in 0..<4 {
      tree1.insert(key: [UInt8(i)], value: [UInt8(i)])
    }

    let tree2 = tree1  // Snapshot

    // Grow tree1 to Node16
    tree1.insert(key: [4], value: [4])
    expectEqual(tree1._root?.type, .node16)
    expectEqual(tree2._root?.type, .node4)

    // Verify both trees independent
    expectEqual(tree1.getValue(key: [4]), [4])
    expectNil(tree2.getValue(key: [4]))

    for i in 0..<4 {
      expectEqual(tree1.getValue(key: [UInt8(i)]), [UInt8(i)])
      expectEqual(tree2.getValue(key: [UInt8(i)]), [UInt8(i)])
    }
  }

  @Test
  func testCOWDuringNode16ToNode4Shrink() {
    var tree1 = ARTree<[UInt8]>()

    // Build Node16
    for i in 0..<5 {
      tree1.insert(key: [UInt8(i)], value: [UInt8(i)])
    }

    let tree2 = tree1  // Snapshot

    // Node16 shrinks to Node4 at count == 3 (hysteresis, like the other node
    // types), so delete down to 3 children to trigger it.
    tree1.delete(key: [4])
    tree1.delete(key: [3])
    expectEqual(tree1._root?.type, .node4)
    expectEqual(tree2._root?.type, .node16)

    // Verify independence
    expectNil(tree1.getValue(key: [4]))
    expectNil(tree1.getValue(key: [3]))
    expectEqual(tree2.getValue(key: [4]), [4])
    expectEqual(tree2.getValue(key: [3]), [3])
  }

  @Test
  func testCOWDuringNode48ToNode256Transition() {
    var tree1 = ARTree<[UInt8]>()

    // Build to Node48
    for i in 0..<48 {
      tree1.insert(key: [UInt8(i)], value: [UInt8(i)])
    }

    let tree2 = tree1  // Snapshot

    // Grow tree1 to Node256
    tree1.insert(key: [48], value: [48])
    expectEqual(tree1._root?.type, .node256)
    expectEqual(tree2._root?.type, .node48)

    // Verify both independent
    expectEqual(tree1.getValue(key: [48]), [48])
    expectNil(tree2.getValue(key: [48]))
  }

  @Test
  func testMultipleSnapshotsDuringTransitions() {
    var tree = ARTree<[UInt8]>()

    // Build Node4
    for i in 0..<4 {
      tree.insert(key: [UInt8(i)], value: [UInt8(i)])
    }
    let snap1 = tree  // Node4

    // Grow to Node16
    tree.insert(key: [4], value: [4])
    let snap2 = tree  // Node16

    // Grow to Node48
    for i in 5..<17 {
      tree.insert(key: [UInt8(i)], value: [UInt8(i)])
    }
    let snap3 = tree  // Node48

    // Verify all snapshots independent
    expectEqual(snap1._root?.type, .node4)
    expectEqual(snap2._root?.type, .node16)
    expectEqual(snap3._root?.type, .node48)

    // Verify counts
    var count1 = 0
    var count2 = 0
    var count3 = 0
    for _ in snap1 { count1 += 1 }
    for _ in snap2 { count2 += 1 }
    for _ in snap3 { count3 += 1 }

    expectEqual(count1, 4)
    expectEqual(count2, 5)
    expectEqual(count3, 17)
  }

  // MARK: - Transition with Prefix Compression

  @Test
  func testNodeTransitionWithLongPrefix() {
    var tree = ARTree<[UInt8]>()

    let prefix: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8]

    // Build Node4 with shared prefix
    for i in 0..<4 {
      tree.insert(key: prefix + [UInt8(i)], value: [UInt8(i)])
    }

    // Grow to Node16 while maintaining prefix
    tree.insert(key: prefix + [4], value: [4])

    // Verify all keys with long prefix intact
    for i in 0..<5 {
      expectEqual(tree.getValue(key: prefix + [UInt8(i)]), [UInt8(i)])
    }
  }

  @Test
  func testNodeTransitionWithPrefixSplit() {
    var tree = ARTree<[UInt8]>()

    // Insert keys with common prefix
    tree.insert(key: [1, 2, 3, 4, 5], value: [1])
    tree.insert(key: [1, 2, 3, 4, 6], value: [2])
    tree.insert(key: [1, 2, 3, 4, 7], value: [3])
    tree.insert(key: [1, 2, 3, 4, 8], value: [4])

    // Insert key that diverges earlier, forcing node creation
    tree.insert(key: [1, 2, 3, 9, 10], value: [5])

    // Verify all keys
    expectEqual(tree.getValue(key: [1, 2, 3, 4, 5]), [1])
    expectEqual(tree.getValue(key: [1, 2, 3, 4, 6]), [2])
    expectEqual(tree.getValue(key: [1, 2, 3, 4, 7]), [3])
    expectEqual(tree.getValue(key: [1, 2, 3, 4, 8]), [4])
    expectEqual(tree.getValue(key: [1, 2, 3, 9, 10]), [5])
  }

  // MARK: - Sparse Key Distribution

  @Test
  func testSparseKeysNode256() {
    var tree = ARTree<[UInt8]>()

    // Insert sparse keys to create Node256
    for i in 0..<49 {
      tree.insert(key: [UInt8(i * 5)], value: [UInt8(i)])
    }

    expectEqual(tree._root?.type, .node256)

    // Verify all keys
    for i in 0..<49 {
      expectEqual(tree.getValue(key: [UInt8(i * 5)]), [UInt8(i)])
    }
  }

  @Test
  func testDenseKeysNode256() {
    var tree = ARTree<[UInt8]>()

    // Insert consecutive keys to create Node256
    for i in 0..<100 {
      tree.insert(key: [UInt8(i)], value: [UInt8(i)])
    }

    expectEqual(tree._root?.type, .node256)

    // Delete many keys
    for i in 0..<50 {
      tree.delete(key: [UInt8(i)])
    }

    // Verify remaining
    for i in 50..<100 {
      expectEqual(tree.getValue(key: [UInt8(i)]), [UInt8(i)])
    }
  }

  // MARK: - Rapid Transition Cycling

  @Test
  func testRapidNode4ToNode16Cycling() {
    var tree = ARTree<[UInt8]>()

    for cycle in 0..<10 {
      // Grow
      for i in 0..<5 {
        tree.insert(key: [UInt8(cycle), UInt8(i)], value: [UInt8(i)])
      }

      // Shrink
      tree.delete(key: [UInt8(cycle), 0])
      tree.delete(key: [UInt8(cycle), 1])
    }

    // Verify final state
    var count = 0
    for _ in tree {
      count += 1
    }

    expectEqual(count, 30)  // 10 cycles * 3 remaining keys each
  }

  @Test
  func testRapidTransitionWithReplace() {
    var tree = ARTree<[UInt8]>()

    // Build to Node16
    for i in 0..<5 {
      tree.insert(key: [UInt8(i)], value: [UInt8(i)])
    }

    // Repeatedly replace values (should not trigger transitions)
    for round in 0..<100 {
      for i in 0..<5 {
        tree.insert(key: [UInt8(i)], value: [UInt8(round)])
      }
    }

    // Should still be Node16
    expectEqual(tree._root?.type, .node16)

    // Verify final values
    for i in 0..<5 {
      expectEqual(tree.getValue(key: [UInt8(i)]), [UInt8(99)])
    }
  }

  // MARK: - Transition Under Load

  @Test
  func testTransitionWithManySnapshots() {
    var trees: [ARTree<[UInt8]>] = []
    var base = ARTree<[UInt8]>()

    // Grow through transitions while taking snapshots
    for i in 0..<50 {
      base.insert(key: [UInt8(i)], value: [UInt8(i)])

      // Take snapshot at each transition boundary
      if i == 3 || i == 4 || i == 16 || i == 48 {
        trees.append(base)
      }
    }

    // Verify each snapshot preserved its node type
    expectEqual(trees[0]._root?.type, .node4)  // 4 keys
    expectEqual(trees[1]._root?.type, .node16)  // 5 keys
    expectEqual(trees[2]._root?.type, .node48)  // 17 keys
    expectEqual(trees[3]._root?.type, .node256)  // 49 keys

    // Verify counts
    var count0 = 0
    var count1 = 0
    var count2 = 0
    var count3 = 0
    for _ in trees[0] { count0 += 1 }
    for _ in trees[1] { count1 += 1 }
    for _ in trees[2] { count2 += 1 }
    for _ in trees[3] { count3 += 1 }

    expectEqual(count0, 4)
    expectEqual(count1, 5)
    expectEqual(count2, 17)
    expectEqual(count3, 49)
  }
}

/// Tests for node transitions with deleteRange operations
@Suite
struct NodeTransitionDeleteRangeTests {

  @Test
  func testDeleteRangeTriggeringNode16ToNode4() {
    var tree = ARTree<[UInt8]>()

    // Build Node16 with 10 keys
    for i in 0..<10 {
      tree.insert(key: [UInt8(i)], value: [UInt8(i)])
    }
    expectEqual(tree._root?.type, .node16)

    // Delete range that shrinks to Node4
    tree.deleteRange(start: [0], end: [6])

    expectEqual(tree._root?.type, .node4)

    // Verify remaining
    for i in 7..<10 {
      expectEqual(tree.getValue(key: [UInt8(i)]), [UInt8(i)])
    }
  }

  @Test
  func testDeleteRangeTriggeringNode48ToNode16() {
    var tree = ARTree<[UInt8]>()

    // Build Node48 with 20 keys
    for i in 0..<20 {
      tree.insert(key: [UInt8(i)], value: [UInt8(i)])
    }
    expectEqual(tree._root?.type, .node48)

    // Delete range that shrinks to Node16
    tree.deleteRange(start: [0], end: [15])

    expectEqual(tree._root?.type, .node16)

    // Verify remaining
    for i in 16..<20 {
      expectEqual(tree.getValue(key: [UInt8(i)]), [UInt8(i)])
    }
  }

  @Test
  func testDeleteRangeTriggeringNode256Shrink() {
    var tree = ARTree<[UInt8]>()

    // Build Node256 with 60 keys
    for i in 0..<60 {
      tree.insert(key: [UInt8(i)], value: [UInt8(i)])
    }
    expectEqual(tree._root?.type, .node256)

    // Delete range
    tree.deleteRange(start: [0], end: [15])

    // Verify remaining keys
    for i in 16..<60 {
      expectEqual(tree.getValue(key: [UInt8(i)]), [UInt8(i)])
    }
  }

  @Test
  func testDeleteRangeCascadingThroughMultipleTransitions() {
    var tree = ARTree<[UInt8]>()

    // Build Node256
    for i in 0..<100 {
      tree.insert(key: [UInt8(i)], value: [UInt8(i)])
    }
    expectEqual(tree._root?.type, .node256)

    // Delete range triggering Node256 -> Node48 -> Node16 -> Node4
    tree.deleteRange(start: [0], end: [96])

    expectEqual(tree._root?.type, .node4)

    // Verify only 3 remain (97, 98, 99)
    expectEqual(tree.getValue(key: [97]), [97])
    expectEqual(tree.getValue(key: [98]), [98])
    expectEqual(tree.getValue(key: [99]), [99])
  }

  @Test
  func testDeleteRangeAtTransitionBoundaryExact() {
    var tree = ARTree<[UInt8]>()

    // Build exactly 5 keys (Node16)
    for i in 0..<5 {
      tree.insert(key: [UInt8(i)], value: [UInt8(i)])
    }
    expectEqual(tree._root?.type, .node16)

    // Delete 2 keys to shrink below Node4 threshold
    tree.deleteRange(start: [3], end: [4])

    // Verify remaining keys
    for i in 0..<3 {
      expectEqual(tree.getValue(key: [UInt8(i)]), [UInt8(i)])
    }
  }
}
