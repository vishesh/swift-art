//===----------------------------------------------------------------------===//
//
// Debug iteration with detailed tracing
//
//===----------------------------------------------------------------------===//

import Testing
@testable import ARTreeModule

@Suite("Debug Iter Test")
struct DebugIterTest {
  typealias Tree = ARTreeImpl<DefaultSpec<Int>>

  @Test
  func testIterationCounts() throws {
    var tree = Tree()

    // Insert 10 items
    for i in 0..<10 {
      tree.insert(key: [UInt8(i)], value: i)
    }

    // Count by iterating multiple times
    var counts: [Int] = []
    for run in 0..<5 {
      var count = 0
      for _ in tree {
        count += 1
        if count > 20 {
          print("Run \(run): Too many items! Stopping at \(count)")
          break
        }
      }
      counts.append(count)
      print("Run \(run): counted \(count) items")
    }

    // All counts should be the same
    for i in 1..<counts.count {
      #expect(counts[i] == counts[0], "Count \(i) (\(counts[i])) != count 0 (\(counts[0]))")
    }
  }

  @Test
  func testFindThreshold() throws {
    // Find the exact number where it breaks
    for n in 1...20 {
      var tree = Tree()
      for i in 0..<n {
        tree.insert(key: [UInt8(i)], value: i)
      }

      var count1 = 0
      for _ in tree { count1 += 1 }

      var count2 = 0
      for _ in tree { count2 += 1 }

      if count1 != count2 {
        print("FAILED at n=\(n): count1=\(count1), count2=\(count2)")
        #expect(false, "Failed at n=\(n)")
        return
      }
    }
    print("All counts up to 20 work correctly")
  }

  @Test
  func testMapSpecifically() throws {
    for n in 1...20 {
      var tree = Tree()
      for i in 0..<n {
        tree.insert(key: [UInt8(i)], value: i)
      }

      // Try map
      do {
        let items = tree.map { $0 }
        if items.count != n {
          print("Map returned wrong count at n=\(n): expected \(n), got \(items.count)")
          #expect(false)
          return
        }
      } catch {
        print("Map failed at n=\(n) with error: \(error)")
        #expect(false)
        return
      }
    }
    print("Map works up to 20 items")
  }
}