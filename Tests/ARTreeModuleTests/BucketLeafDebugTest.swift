//===----------------------------------------------------------------------===//
//
// Debug test for bucket leaf iteration issues
//
//===----------------------------------------------------------------------===//

import Testing
@testable import ARTreeModule

@Suite("BucketLeaf Debug")
struct BucketLeafDebugTest {
  typealias Tree = ARTreeImpl<DefaultSpec<Int>>

  @Test
  func testSimpleIteration() throws {
    var tree = Tree()

    // Insert just 3 items
    tree.insert(key: [0], value: 0)
    tree.insert(key: [1], value: 1)
    tree.insert(key: [2], value: 2)

    // Count by iterating
    var count1 = 0
    for _ in tree {
      count1 += 1
    }
    print("First count: \(count1)")

    // Count again
    var count2 = 0
    for _ in tree {
      count2 += 1
    }
    print("Second count: \(count2)")

    #expect(count1 == 3)
    #expect(count2 == 3)
    #expect(count1 == count2)
  }

  @Test
  func testIterationValues() throws {
    var tree = Tree()

    // Insert just 3 items
    tree.insert(key: [0], value: 0)
    tree.insert(key: [1], value: 1)
    tree.insert(key: [2], value: 2)

    // Collect values
    var values1: [Int] = []
    for (_, v) in tree {
      values1.append(v)
    }

    var values2: [Int] = []
    for (_, v) in tree {
      values2.append(v)
    }

    #expect(values1 == [0, 1, 2])
    #expect(values2 == [0, 1, 2])
    #expect(values1 == values2)
  }

  @Test
  func testReverseInsertOrder() throws {
    var tree = Tree()

    // Insert in reverse order (like the failing test)
    for i in (0..<50).reversed() {
      tree.insert(key: [UInt8(i)], value: i)
    }

    // Count by iterating
    var count1 = 0
    for _ in tree {
      count1 += 1
    }

    var count2 = 0
    for _ in tree {
      count2 += 1
    }

    #expect(count1 == 50)
    #expect(count2 == 50)
  }

  @Test
  func testUsingMap() throws {
    var tree = Tree()

    // Insert a few items
    for i in 0..<10 {
      tree.insert(key: [UInt8(i)], value: i)
    }

    // Use map (this is what triggers the error)
    let items = tree.map { $0 }
    #expect(items.count == 10)
  }
}