import Testing
@testable import ARTreeModule
import _CollectionsTestSupport

@Suite
struct ARTreeDeleteRangeTests {
  @Test
  func testDeleteRangeBasic() {
    var tree = ARTree<[UInt8]>()

    // Insert keys 0-9
    for i in 0..<10 {
      tree.insert(key: [UInt8(i)], value: [UInt8(i)])
    }

    // Delete keys 3-6 (inclusive)
    tree.deleteRange(start: [3], end: [6])

    // Verify keys 0-2 and 7-9 remain
    for i in 0..<3 {
      expectEqual(tree.getValue(key: [UInt8(i)]), [UInt8(i)])
    }
    for i in 3...6 {
      expectNil(tree.getValue(key: [UInt8(i)]))
    }
    for i in 7..<10 {
      expectEqual(tree.getValue(key: [UInt8(i)]), [UInt8(i)])
    }
  }

  @Test
  func testDeleteRangeEmpty() {
    var tree = ARTree<[UInt8]>()

    // Delete from empty tree (should not crash)
    tree.deleteRange(start: [0], end: [10])

    expectEqual(tree._root, nil)
  }

  @Test
  func testDeleteRangeNoMatch() {
    var tree = ARTree<[UInt8]>()

    // Insert keys 10, 20, 30
    tree.insert(key: [10], value: [10])
    tree.insert(key: [20], value: [20])
    tree.insert(key: [30], value: [30])

    // Delete range that doesn't match any keys
    tree.deleteRange(start: [0], end: [5])

    // All keys should remain
    expectEqual(tree.getValue(key: [10]), [10])
    expectEqual(tree.getValue(key: [20]), [20])
    expectEqual(tree.getValue(key: [30]), [30])
  }

  @Test
  func testDeleteRangeAll() {
    var tree = ARTree<[UInt8]>()

    // Insert keys 0-9
    for i in 0..<10 {
      tree.insert(key: [UInt8(i)], value: [UInt8(i)])
    }

    // Delete all keys
    tree.deleteRange(start: [0], end: [255])

    // Tree should be empty
    var count = 0
    for _ in tree {
      count += 1
    }
    expectEqual(count, 0)
  }

  @Test
  func testDeleteRangePartialOverlap() {
    var tree = ARTree<[UInt8]>()

    // Insert keys with shared prefix
    tree.insert(key: [1, 2, 3], value: [1])
    tree.insert(key: [1, 2, 4], value: [2])
    tree.insert(key: [1, 3, 3], value: [3])
    tree.insert(key: [2, 2, 3], value: [4])

    // Delete range [1,2,0] to [1,2,255] (should delete first two)
    tree.deleteRange(start: [1, 2, 0], end: [1, 2, 255])

    expectNil(tree.getValue(key: [1, 2, 3]))
    expectNil(tree.getValue(key: [1, 2, 4]))
    expectEqual(tree.getValue(key: [1, 3, 3]), [3])
    expectEqual(tree.getValue(key: [2, 2, 3]), [4])
  }

  @Test
  func testDeleteRangeInvertedBounds() {
    var tree = ARTree<[UInt8]>()

    // Insert keys 0-9
    for i in 0..<10 {
      tree.insert(key: [UInt8(i)], value: [UInt8(i)])
    }

    // Delete with start > end (should delete nothing)
    tree.deleteRange(start: [8], end: [3])

    // All keys should remain
    for i in 0..<10 {
      expectEqual(tree.getValue(key: [UInt8(i)]), [UInt8(i)])
    }
  }

  @Test
  func testDeleteRangeSingleKey() {
    var tree = ARTree<[UInt8]>()

    // Insert keys 0-9
    for i in 0..<10 {
      tree.insert(key: [UInt8(i)], value: [UInt8(i)])
    }

    // Delete single key using range
    tree.deleteRange(start: [5], end: [5])

    // Only key 5 should be deleted
    for i in 0..<10 {
      if i == 5 {
        expectNil(tree.getValue(key: [UInt8(i)]))
      } else {
        expectEqual(tree.getValue(key: [UInt8(i)]), [UInt8(i)])
      }
    }
  }

  @Test
  func testDeleteRangeLargeScale() {
    var tree = ARTree<[UInt8]>()

    // Insert 256 keys
    for i in 0..<256 {
      tree.insert(key: [UInt8(i), 0], value: [UInt8(i)])
    }

    // Delete middle third
    tree.deleteRange(start: [85, 0], end: [170, 0])

    // Verify first third remains
    for i in 0..<85 {
      expectEqual(tree.getValue(key: [UInt8(i), 0]), [UInt8(i)])
    }

    // Verify middle third is gone
    for i in 85...170 {
      expectNil(tree.getValue(key: [UInt8(i), 0]))
    }

    // Verify last third remains
    for i in 171..<256 {
      expectEqual(tree.getValue(key: [UInt8(i), 0]), [UInt8(i)])
    }

    // Count remaining
    var count = 0
    for _ in tree {
      count += 1
    }
    expectEqual(count, 256 - (170 - 85 + 1))
  }
}

// Test with String keys
@Suite
struct RadixTreeDeleteRangeTests {
  @Test
  func testDeleteRangeStrings() {
    var tree = RadixTree<String, Int>()

    // Insert string keys
    tree["apple"] = 1
    tree["apricot"] = 2
    tree["banana"] = 3
    tree["cherry"] = 4
    tree["date"] = 5

    // Delete range from "b" to "cherry" (inclusive)
    tree.removeValues(from: "b", to: "cherry")

    // Verify "apple" and "apricot" remain
    expectEqual(tree["apple"], 1)
    expectEqual(tree["apricot"], 2)

    // Verify "banana" and "cherry" are deleted
    expectNil(tree["banana"])
    expectNil(tree["cherry"])

    // Verify "date" remains
    expectEqual(tree["date"], 5)
  }

  @Test
  func testDeleteRangePrefixStrings() {
    var tree = RadixTree<String, Int>()

    // Insert keys with common prefixes
    tree["test1"] = 1
    tree["test2"] = 2
    tree["test3"] = 3
    tree["testing"] = 4
    tree["other"] = 5

    // Delete range "test1" to "test3"
    tree.removeValues(from: "test1", to: "test3")

    expectNil(tree["test1"])
    expectNil(tree["test2"])
    expectNil(tree["test3"])
    expectEqual(tree["testing"], 4)
    expectEqual(tree["other"], 5)
  }
}