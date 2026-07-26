// MARK: Range scans
@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension RadixTree {
  /// Calls `body` for each key-value pair whose key is in the closed range
  /// `[lowerBound, upperBound]`, in ascending key order.
  ///
  /// Ordering follows the keys' binary-comparable byte encoding (which matches the
  /// natural order for the supported key types). If `lowerBound > upperBound`, no
  /// pair is visited.
  ///
  /// - Complexity: O(`m` + `b`) where `m` is the number of pairs visited and `b`
  ///   is the bounded portion of the tree along the range's two edges — the tree
  ///   prunes any subtree that lies entirely outside the range.
  public func forEachEntry(
    from lowerBound: Key, to upperBound: Key, _ body: (Key, Value) -> Void
  ) {
    lowerBound.withUnsafeBinaryComparableBytes { lo in
      upperBound.withUnsafeBinaryComparableBytes { hi in
        _tree.forEachInRange(lowerBytes: lo, upperBytes: hi) { keyBytes, value in
          body(Key.fromBinaryComparableBytes(keyBytes), value)
        }
      }
    }
  }

  /// Returns the first key-value pair whose key is `>= lowerBound`, in ascending
  /// key order (the successor-or-equal / "ceiling" entry), or `nil` if every key
  /// is smaller.
  ///
  /// The descent is O(`k`) in the key's byte length and independent of the number
  /// of entries — a comparison-based ordered map instead pays O(log n) key
  /// comparisons, each re-scanning any shared prefix. This is the radix tree's
  /// signature ordered operation.
  public func firstEntry(from lowerBound: Key) -> (key: Key, value: Value)? {
    var result: (key: Key, value: Value)?
    lowerBound.withUnsafeBinaryComparableBytes { lo in
      _tree.forEachFrom(lowerBytes: lo) { keyBytes, value in
        result = (Key.fromBinaryComparableBytes(keyBytes), value)
        return false  // stop at the first match
      }
      return  // keep the byte-accessor closure returning Void
    }
    return result
  }

  /// Returns the key-value pairs whose key is in the closed range
  /// `[lowerBound, upperBound]`, in ascending key order.
  public func entries(from lowerBound: Key, to upperBound: Key) -> [(key: Key, value: Value)] {
    var result: [(key: Key, value: Value)] = []
    forEachEntry(from: lowerBound, to: upperBound) { result.append((key: $0, value: $1)) }
    return result
  }
}
