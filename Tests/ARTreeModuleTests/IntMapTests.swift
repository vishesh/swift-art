import Testing
import _CollectionsTestSupport
@testable import ARTreeModule

fileprivate func randomInts<T: FixedWidthInteger>(size: Int,
                                                  unique: Bool,
                                                  min: T,
                                                  max: T) -> [T] {

  if unique {
    assert(max - min + 1 >= size, "range not large enough")
    var uniques = Set<T>()
    while uniques.count < size {
      uniques.insert(.random(in: min...max))
    }
    return Array(uniques)
  } else {
    return (0..<size - 1).map { _ in .random(in: min...max) }
  }
}

final class IntMapTests: CollectionTestCase {
  func _testCommon<T: FixedWidthInteger & ConvertibleToBinaryComparableBytes>(size: Int,
                                         unique: Bool,
                                         min: T,
                                         max: T,
                                         debug: Bool = false) throws {
    let testCase: [(T, Int)] = Array(
      randomInts(size: size,
                 unique: unique,
                 min: min,
                 max: max)
        .enumerated())
      .map { (v, k) in (k, v) }

    var t = RadixTree<T, Int>()
    var m: [T: Int] = [:]
    for (k, v) in testCase {
      if debug {
        print("Inserting \(k) --> \(v)")
      }
      _ = t.updateValue(v, forKey: k)
      m[k] = v
    }

    var total = 0
    var last = T.min
    for (k, v) in t {
      if debug {
        print("Fetched \(k) --> \(v)")
      }

      expectEqual(v, m[k])

      if total > 1 {
        expectLessThanOrEqual(last, k, "keys should be ordered")
      }
      last = k

      total += 1
      if total > m.count {
        break
      }
    }

    expectEqual(total, m.count)
  }

  @Test func testUnsignedIntUniqueSmall() throws {
    try _testCommon(size: 100,
                    unique: true,
                    min: 0 as UInt,
                    max: 1_000 as UInt)
  }

  @Test func testUnsignedIntUniqueLarge() throws {
    try _testCommon(size: 100_000,
                    unique: true,
                    min: 0 as UInt,
                    max: 1 << 50 as UInt)
  }

  @Test func testUnsignedIntWithDuplicatesSmallSet() throws {
    try _testCommon(size: 100,
                    unique: false,
                    min: 0 as UInt,
                    max: 50 as UInt)
  }

  @Test func testUnsignedInt32WithDuplicatesSmallSet() throws {
    try _testCommon(size: 100,
                    unique: false,
                    min: 0 as UInt32,
                    max: 50 as UInt32)
  }

  @Test func testUnsignedIntWithDuplicatesLargeSet() throws {
    try _testCommon(size: 1_000_000,
                    unique: false,
                    min: 0 as UInt,
                    max: 100_000 as UInt)
  }

  @Test func testSignedIntUniqueSmall() throws {
    try _testCommon(size: 100,
                    unique: true,
                    min: -100 as Int,
                    max: 100 as Int,
                    debug: false)
  }

  @Test func testSignedIntUniqueLarge() throws {
    try _testCommon(size: 1_000_000,
                    unique: true,
                    min: -100_000_000 as Int,
                    max: 100_000_000 as Int)
  }
}
