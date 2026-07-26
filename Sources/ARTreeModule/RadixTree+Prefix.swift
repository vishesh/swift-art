// MARK: Prefix scans
@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension RadixTree {
  /// Calls `body` for each key-value pair whose key starts with the given prefix,
  /// in ascending key order.
  ///
  /// - Note: For String keys, prefix matching has limitations due to null-termination.
  ///   The prefix "app" will not match "apple" because internally "app\0" is not
  ///   a prefix of "apple\0". Use this method primarily with byte array keys.
  ///
  /// - Parameters:
  ///   - prefix: The prefix to match against.
  ///   - body: A closure called with each matching key-value pair.
  /// - Complexity: O(`m` + `log n`) where `m` is the number of matching pairs
  ///   and `n` is the total number of pairs in the tree.
  public func forEachEntry(withPrefix prefix: Key, _ body: (Key, Value) -> Void) {
    prefix.withUnsafeBinaryComparableBytes { prefixBytes in
      _tree.forEachWithPrefix(prefixBytes) { keyBytes, value in
        body(Key.fromBinaryComparableBytes(keyBytes), value)
      }
    }
  }

  /// Returns all key-value pairs whose key starts with the given prefix,
  /// in ascending key order.
  ///
  /// - Parameter prefix: The prefix to match against.
  /// - Returns: Array of matching key-value pairs.
  /// - Complexity: O(`m` + `log n`) where `m` is the number of matching pairs
  ///   and `n` is the total number of pairs in the tree.
  public func entries(withPrefix prefix: Key) -> [(key: Key, value: Value)] {
    var result: [(key: Key, value: Value)] = []
    forEachEntry(withPrefix: prefix) { key, value in
      result.append((key: key, value: value))
    }
    return result
  }
}
