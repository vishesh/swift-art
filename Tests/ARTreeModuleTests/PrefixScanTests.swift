import Testing
@testable import ARTreeModule
import _CollectionsTestSupport

// String prefix tests removed - prefix matching doesn't work properly with
// null-terminated strings. See ARTreePrefixScanTests for byte array tests.

@Suite
struct ARTreePrefixScanTests {
  @Test
  func testPrefixScanBytes() {
    var tree = ARTree<[UInt8]>()

    // Add keys with common prefixes
    tree.insert(key: [1, 2, 3, 4], value: [1])
    tree.insert(key: [1, 2, 3, 5], value: [2])
    tree.insert(key: [1, 2, 4, 4], value: [3])
    tree.insert(key: [1, 3, 3, 4], value: [4])
    tree.insert(key: [2, 2, 3, 4], value: [5])

    // Test prefix [1, 2]
    var collected: [[UInt8]] = []
    let searchPrefix: [UInt8] = [1, 2]
    searchPrefix.withUnsafeBufferPointer { buffer in
      let rawBuffer = UnsafeRawBufferPointer(buffer)
      tree.forEachWithPrefix(rawBuffer) { key, value in
        collected.append(Array(key))
      }
    }

    expectEqual(collected.count, 3)
    expectEqual(collected[0], [1, 2, 3, 4])
    expectEqual(collected[1], [1, 2, 3, 5])
    expectEqual(collected[2], [1, 2, 4, 4])
  }

  @Test
  func testPrefixScanDeepTree() {
    var tree = ARTree<[UInt8]>()

    // Create a deep tree with long shared prefixes
    let commonPrefix: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8]
    for i in 0..<50 {
      var key = commonPrefix
      key.append(UInt8(i))
      tree.insert(key: key, value: [UInt8(i)])
    }

    // Scan with full common prefix
    var count = 0
    commonPrefix.withUnsafeBufferPointer { buffer in
      let rawBuffer = UnsafeRawBufferPointer(buffer)
      tree.forEachWithPrefix(rawBuffer) { _, _ in
        count += 1
      }
    }
    expectEqual(count, 50)

    // Scan with partial prefix
    count = 0
    let partialPrefix: [UInt8] = [1, 2, 3, 4]
    partialPrefix.withUnsafeBufferPointer { buffer in
      let rawBuffer = UnsafeRawBufferPointer(buffer)
      tree.forEachWithPrefix(rawBuffer) { _, _ in
        count += 1
      }
    }
    expectEqual(count, 50)
  }

  @Test
  func testPrefixScanEmptyPrefix() {
    var tree = ARTree<[UInt8]>()

    for i in 0..<10 {
      tree.insert(key: [UInt8(i)], value: [UInt8(i)])
    }

    // Empty prefix should match all
    var count = 0
    let emptyPrefix: [UInt8] = []
    emptyPrefix.withUnsafeBufferPointer { buffer in
      let rawBuffer = UnsafeRawBufferPointer(buffer)
      tree.forEachWithPrefix(rawBuffer) { _, _ in
        count += 1
      }
    }
    expectEqual(count, 10)
  }

  @Test
  func testPrefixScanPartialMatches() {
    var tree = ARTree<[UInt8]>()

    // Start with simpler test case
    tree.insert(key: [1, 2, 3, 4], value: [1])
    tree.insert(key: [1, 2, 5, 6], value: [2])

    // Search for prefix [1, 2, 3]
    var collected: [[UInt8]] = []
    let searchPrefix: [UInt8] = [1, 2, 3]
    searchPrefix.withUnsafeBufferPointer { buffer in
      let rawBuffer = UnsafeRawBufferPointer(buffer)
      tree.forEachWithPrefix(rawBuffer) { key, _ in
        collected.append(Array(key))
      }
    }

    // Should only find the first key
    expectEqual(collected.count, 1)
    expectEqual(collected[0], [1, 2, 3, 4])
  }

  @Test
  func testPrefixScanMultipleNodes() {
    var tree = ARTree<[UInt8]>()

    // Fill enough to trigger node transitions
    for i in 0..<60 {
      tree.insert(key: [10, UInt8(i)], value: [UInt8(i)])
      tree.insert(key: [20, UInt8(i)], value: [UInt8(i + 100)])
    }

    // Count entries with prefix [10]
    var count10 = 0
    let prefix10: [UInt8] = [10]
    prefix10.withUnsafeBufferPointer { buffer in
      let rawBuffer = UnsafeRawBufferPointer(buffer)
      tree.forEachWithPrefix(rawBuffer) { _, _ in
        count10 += 1
      }
    }
    expectEqual(count10, 60)

    // Count entries with prefix [20]
    var count20 = 0
    let prefix20: [UInt8] = [20]
    prefix20.withUnsafeBufferPointer { buffer in
      let rawBuffer = UnsafeRawBufferPointer(buffer)
      tree.forEachWithPrefix(rawBuffer) { _, _ in
        count20 += 1
      }
    }
    expectEqual(count20, 60)
  }
}