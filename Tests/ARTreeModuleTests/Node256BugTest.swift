// Test to verify Node48 to Node256 transition correctness
// Specifically checking for potential issues with slot value handling

import Testing
@testable import ARTreeModule
import _CollectionsTestSupport

@Suite
struct Node256TransitionTests {
  @Test
  func testNode48ToNode256TransitionPreservesAllChildren() {
    // This test verifies that when a Node48 transitions to Node256,
    // all 48 children are correctly preserved.
    // The potential bug is in Node256.swift:42 where `slot < 0xFF`
    // should potentially be `slot != 0xFF` for consistency.

    var tree = ARTree<[UInt8]>()

    // We need to create enough children to force the transitions:
    // Node4 (4 children) -> Node16 (16 children) -> Node48 (48 children) -> Node256

    // Add children to fill up to Node48
    for i in 0..<48 {
      tree.insert(key: [UInt8(i)], value: [UInt8(i)])
    }

    // Verify all 48 values are present before transition
    for i in 0..<48 {
      let value = tree.getValue(key: [UInt8(i)])
      expectEqual(value, [UInt8(i)],
                  "Value at key \(i) should exist before Node256 transition")
    }

    // Add one more child to trigger Node48 -> Node256 transition
    tree.insert(key: [48], value: [48])

    // Verify all 49 values are present after transition
    for i in 0..<49 {
      let value = tree.getValue(key: [UInt8(i)])
      expectEqual(value, [UInt8(i)],
                  "Value at key \(i) should exist after Node256 transition")
    }

    // Additional verification: count should be correct
    var count = 0
    for _ in tree {
      count += 1
    }
    expectEqual(count, 49, "Tree should have exactly 49 entries")
  }

  @Test
  func testNode48ToNode256WithSparseKeys() {
    // Test with non-consecutive keys to ensure slot mapping is correct
    var tree = ARTree<[UInt8]>()

    // Create a sparse set of keys that will still fill Node48
    var keys: [UInt8] = []

    // Use keys that are spread across the 0-255 range
    // This tests that the slot mapping is correctly preserved
    for i in 0..<48 {
      let key = UInt8((i * 5) % 256)
      keys.append(key)
      tree.insert(key: [key], value: [key])
    }

    // Verify all values before transition
    for key in keys {
      let value = tree.getValue(key: [key])
      expectEqual(value, [key],
                  "Value at key \(key) should exist before Node256 transition")
    }

    // Find a key not in our set to trigger the transition
    var triggerKey: UInt8 = 0
    for candidate in UInt8(0)...UInt8(255) {
      if !keys.contains(candidate) {
        triggerKey = candidate
        break
      }
    }

    // Add the trigger key to cause Node48 -> Node256 transition
    tree.insert(key: [triggerKey], value: [triggerKey])
    keys.append(triggerKey)

    // Verify all values after transition
    for key in keys {
      let value = tree.getValue(key: [key])
      expectEqual(value, [key],
                  "Value at key \(key) should exist after Node256 transition")
    }

    // Verify count
    var count = 0
    for _ in tree {
      count += 1
    }
    expectEqual(count, 49, "Tree should have exactly 49 entries")
  }

  @Test
  func testNode48MaxSlotUsage() {
    // This test specifically tries to use all 48 slots in Node48
    // and verifies the transition preserves them all
    var tree = ARTree<[UInt8]>()

    // Add exactly 48 distinct keys
    let testKeys = Array(0..<48).map { UInt8($0 * 2) } // Even numbers 0, 2, 4, ..., 94

    for key in testKeys {
      tree.insert(key: [key, 255], value: [key])  // Add second byte to avoid leaf optimization
    }

    // Check internal structure - should be Node48
    let rootType = tree._root?.type
    expectEqual(rootType, .node48, "Root should be Node48 with 48 children")

    // Trigger transition to Node256
    tree.insert(key: [99, 255], value: [99])

    // Check internal structure - should now be Node256
    let newRootType = tree._root?.type
    expectEqual(newRootType, .node256, "Root should be Node256 after adding 49th child")

    // Verify all original values survived the transition
    for key in testKeys {
      let value = tree.getValue(key: [key, 255])
      expectEqual(value, [key],
                  "Value at key [\(key), 255] should exist after Node256 transition")
    }

    // Verify the new value
    expectEqual(tree.getValue(key: [99, 255]), [99],
                "New value should exist after transition")
  }
}