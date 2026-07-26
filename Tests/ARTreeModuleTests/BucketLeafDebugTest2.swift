//===----------------------------------------------------------------------===//
//
// Debug test to isolate bucket leaf iteration issue
//
//===----------------------------------------------------------------------===//

import Testing
@testable import ARTreeModule

@Suite("BucketLeaf Debug2")
struct BucketLeafDebugTest2 {
  typealias Tree = ARTreeImpl<DefaultSpec<Int>>

  @Test
  func testExactlyFourItems() throws {
    var tree = Tree()

    // Try with exactly 4 items (might trigger Node4 creation)
    for i in 0..<4 {
      tree.insert(key: [UInt8(i)], value: i)
    }

    var count1 = 0
    for _ in tree { count1 += 1 }

    var count2 = 0
    for _ in tree { count2 += 1 }

    #expect(count1 == 4, "First count should be 4, got \(count1)")
    #expect(count2 == 4, "Second count should be 4, got \(count2)")
  }

  @Test
  func testExactlyFiveItems() throws {
    var tree = Tree()

    // Try with exactly 5 items (might trigger Node4 -> Node16 transition)
    for i in 0..<5 {
      tree.insert(key: [UInt8(i)], value: i)
    }

    var count1 = 0
    for _ in tree { count1 += 1 }

    var count2 = 0
    for _ in tree { count2 += 1 }

    #expect(count1 == 5, "First count should be 5, got \(count1)")
    #expect(count2 == 5, "Second count should be 5, got \(count2)")
  }

  @Test
  func testPrintStructure() throws {
    var tree = Tree()

    // Insert items that will be in same bucket
    for i in 0..<10 {
      tree.insert(key: [UInt8(i)], value: i)
    }

    print("Tree structure:")
    if let root = tree._root {
      print("Root type: \(root.type)")
    }

    // Try to iterate and see what happens
    var items: [(Key, Int)] = []
    for item in tree {
      items.append(item)
      if items.count > 20 {
        print("ERROR: Too many items, stopping")
        break
      }
    }

    print("Found \(items.count) items")
    for (i, (key, value)) in items.enumerated() {
      print("  [\(i)]: key=\(key), value=\(value)")
    }

    #expect(items.count == 10)

    // Now try using map
    let mapped = tree.map { $0 }
    #expect(mapped.count == 10, "Map should return 10 items")
  }
}