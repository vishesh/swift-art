// MARK: Hashable conformance

@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension RadixTree: Hashable where Key: Hashable, Value: Hashable {
  /// Hashes the essential components of the tree by combining the count
  /// and all key-value pairs in order.
  ///
  /// The hash value is consistent with equality: two trees that compare equal
  /// will have the same hash value.
  ///
  /// - Parameter hasher: The hasher to use when combining the components
  /// - Complexity: O(n) where n is the number of elements
  public func hash(into hasher: inout Hasher) {
    // Include count to quickly differentiate trees of different sizes
    hasher.combine(count)

    // Hash all elements in order
    // Order matters for ordered collections
    for (key, value) in self {
      hasher.combine(key)
      hasher.combine(value)
    }
  }
}