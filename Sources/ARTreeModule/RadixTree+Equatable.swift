// MARK: Equatable conformance

@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension RadixTree: Equatable where Key: Equatable, Value: Equatable {
  /// Returns a Boolean value indicating whether two trees contain the same elements
  /// in the same order.
  ///
  /// For ordered collections like RadixTree, equality means both trees must contain
  /// the exact same key-value pairs in the exact same order.
  ///
  /// - Parameters:
  ///   - lhs: A tree to compare
  ///   - rhs: Another tree to compare
  /// - Returns: true if both trees contain the same elements in the same order
  /// - Complexity: O(n) where n is the number of elements
  public static func == (lhs: RadixTree, rhs: RadixTree) -> Bool {
    // Quick check: different counts mean not equal
    if lhs.count != rhs.count {
      return false
    }

    // Empty trees are equal
    if lhs.isEmpty {
      return true
    }

    // Compare element by element in order
    for (left, right) in zip(lhs, rhs) {
      if left.0 != right.0 || left.1 != right.1 {
        return false
      }
    }

    return true
  }
}