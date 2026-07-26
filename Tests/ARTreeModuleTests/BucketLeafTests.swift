//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift ART open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

import Testing
@testable import ARTreeModule

@Suite("BucketLeaf Tests")
struct BucketLeafTests {
  typealias Tree = ARTreeImpl<DefaultSpec<Int>>

  @Test
  func testBucketLeafBasics() throws {
    var tree = Tree()

    // Insert entries that will go into bucket leaves
    for i in 0..<100 {
      let key = [UInt8(i)]
      tree.insert(key: key, value: i)
    }

    // Verify all values can be retrieved
    for i in 0..<100 {
      let key = [UInt8(i)]
      let value = tree.getValue(key: key)
      #expect(value == i, "Value mismatch for key \(i)")
    }
  }

  @Test
  func testBucketLeafInsertOrder() throws {
    var tree = Tree()

    // Insert in reverse order
    for i in (0..<50).reversed() {
      let key = [UInt8(i)]
      tree.insert(key: key, value: i)
    }

    // Insert in forward order
    for i in 50..<100 {
      let key = [UInt8(i)]
      tree.insert(key: key, value: i)
    }

    // Verify all values are present and correctly ordered
    let collected = tree.map { $0 }
    #expect(collected.count == 100)

    for (index, (key, value)) in collected.enumerated() {
      #expect(key == [UInt8(index)])
      #expect(value == index)
    }
  }

  @Test
  func testBucketLeafDeletion() throws {
    var tree = Tree()

    // Fill tree
    for i in 0..<100 {
      let key = [UInt8(i)]
      tree.insert(key: key, value: i)
    }

    // Delete every other entry
    for i in stride(from: 0, to: 100, by: 2) {
      let key = [UInt8(i)]
      tree.delete(key: key)
    }

    // Verify only odd entries remain
    for i in 0..<100 {
      let key = [UInt8(i)]
      let value = tree.getValue(key: key)
      if i % 2 == 0 {
        #expect(value == nil, "Even key \(i) should be deleted")
      } else {
        #expect(value == i, "Odd key \(i) should remain")
      }
    }
  }

  @Test
  func testBucketLeafIteration() throws {
    var tree = Tree()
    let entries = 50

    // Insert entries
    for i in 0..<entries {
      let key = [UInt8(i), UInt8(i * 2)]
      tree.insert(key: key, value: i)
    }

    // Test forward iteration
    var prev = -1
    for (_, value) in tree {
      #expect(value > prev, "Values should be in order")
      prev = value
    }

    // Test backward iteration (BidirectionalCollection)
    let indices = Array(tree.indices)
    for i in (1..<indices.count).reversed() {
      let (_, v1) = tree[indices[i - 1]]
      let (_, v2) = tree[indices[i]]
      #expect(v1 < v2, "Values should be ordered")
    }
  }

  @Test
  func testBucketLeafCapacity() throws {
    var tree = Tree()

    // Insert enough entries to force bucket splits
    // Use keys with shared prefix to ensure they go to same bucket initially
    for i in 0..<64 {  // More than bucket capacity of 32
      let key = [UInt8(100), UInt8(i)]
      tree.insert(key: key, value: i)
    }

    // Verify all values are retrievable
    for i in 0..<64 {
      let key = [UInt8(100), UInt8(i)]
      let value = tree.getValue(key: key)
      #expect(value == i, "Value mismatch after bucket split")
    }

    // Verify iteration order
    let collected = tree.compactMap { (k, v) -> Int? in
      if k[0] == 100 { return v }
      return nil
    }
    #expect(collected.count == 64)
    #expect(collected == Array(0..<64))
  }

  @Test
  func testBucketLeafCOW() throws {
    var tree1 = Tree()

    // Insert initial data
    for i in 0..<50 {
      let key = [UInt8(i)]
      tree1.insert(key: key, value: i)
    }

    // Create copy
    var tree2 = tree1

    // Modify original
    for i in 50..<100 {
      let key = [UInt8(i)]
      tree1.insert(key: key, value: i)
    }

    // Modify copy differently
    for i in 0..<25 {
      let key = [UInt8(i)]
      tree2.delete(key: key)
    }

    // Verify original has 100 entries
    #expect(tree1.count == 100)

    // Verify copy has 25 entries (50 - 25)
    #expect(tree2.count == 25)

    // Verify correct values in each tree
    for i in 0..<100 {
      let key = [UInt8(i)]
      let v1 = tree1.getValue(key: key)
      let v2 = tree2.getValue(key: key)

      if i < 25 {
        #expect(v1 == i)
        #expect(v2 == nil)
      } else if i < 50 {
        #expect(v1 == i)
        #expect(v2 == i)
      } else {
        #expect(v1 == i)
        #expect(v2 == nil)
      }
    }
  }

  @Test
  func testBucketLeafMixedOperations() throws {
    var tree = Tree()
    var reference: [Int: Int] = [:]

    // Mixed insert/delete/update operations
    for _ in 0..<200 {
      let key = Int.random(in: 0..<100)
      let operation = Int.random(in: 0..<3)

      switch operation {
      case 0:  // Insert/Update
        let value = Int.random(in: 0..<1000)
        tree.insert(key: [UInt8(key)], value: value)
        reference[key] = value

      case 1:  // Delete
        tree.delete(key: [UInt8(key)])
        reference[key] = nil

      default:  // Query
        let treeValue = tree.getValue(key: [UInt8(key)])
        let refValue = reference[key]
        #expect(treeValue == refValue)
      }
    }

    // Final verification
    for key in 0..<100 {
      let treeValue = tree.getValue(key: [UInt8(key)])
      let refValue = reference[key]
      #expect(treeValue == refValue)
    }
  }
}