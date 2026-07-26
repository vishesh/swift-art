//===----------------------------------------------------------------------===//
//
// Simple test to debug iteration
//
//===----------------------------------------------------------------------===//

import Testing
@testable import ARTreeModule

@Suite("Simple Iter Test")
struct SimpleIterTest {
  typealias Tree = ARTreeImpl<DefaultSpec<Int>>

  @Test
  func testDirectIteration() throws {
    var tree = Tree()

    // Insert just 5 items
    for i in 0..<5 {
      tree.insert(key: [UInt8(i)], value: i)
    }

    print("Tree created with 5 items")

    // Create two iterators
    var iter1 = tree.makeIterator()
    var iter2 = tree.makeIterator()

    // Collect from both
    var items1: [Int] = []
    while let (_, v) = iter1.next() {
      items1.append(v)
    }

    var items2: [Int] = []
    while let (_, v) = iter2.next() {
      items2.append(v)
    }

    print("Iter1: \(items1)")
    print("Iter2: \(items2)")

    #expect(items1 == items2, "Iterators should produce same results")
    #expect(items1 == [0, 1, 2, 3, 4])
  }

  @Test
  func testCountVsIteration() throws {
    var tree = Tree()

    // Insert items
    for i in 0..<5 {
      tree.insert(key: [UInt8(i)], value: i)
    }

    // Count using iteration
    var count1 = 0
    for _ in tree {
      count1 += 1
    }

    // Count again
    var count2 = 0
    for _ in tree {
      count2 += 1
    }

    // Collect items
    var items: [Int] = []
    for (_, v) in tree {
      items.append(v)
    }

    print("Count1: \(count1)")
    print("Count2: \(count2)")
    print("Items count: \(items.count)")

    #expect(count1 == 5)
    #expect(count2 == 5)
    #expect(items.count == 5)
  }

  @Test
  func testWith10Items() throws {
    var tree = Tree()

    // Insert items - this should create internal nodes
    for i in 0..<10 {
      tree.insert(key: [UInt8(i)], value: i)
    }

    // Try using map - this is what fails
    let items = tree.map { $0 }
    #expect(items.count == 10)
  }
}