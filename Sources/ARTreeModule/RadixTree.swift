/// A collection which maintains key-value pairs in compact and sorted order. The keys must confirm
/// to `ConvertibleToBinaryComparableBytes`, i.e. the keys can be converted to bytes, and the order
/// of key is defined by order of these bytes.
///
/// `RadixTree` is optimized for space, mutating shared copies, and efficient range operations.
/// Compared to `SortedDictionary` in collection library, `RadixTree` is ideal for datasets where
/// keys often have common prefixes, or key comparison is expensive as `RadixTree` operations are
/// often O(k) instead of O(log(n)) where `k` is key length and `n` is number of items in
/// collection.
///
/// `RadixTree` has the same functionality as a standard `Dictionary`, and it largely implements the
/// same APIs. However, `RadixTree` is optimized specifically for use cases where underlying keys
/// share common prefixes. The underlying data-structure is a _persistent_ variant of _Adaptive Radix
/// Tree (ART)_.
public struct RadixTree<Key: ConvertibleToBinaryComparableBytes, Value> {
  internal var _tree: ARTree<Value>

  /// Creates an empty tree.
  ///
  /// - Complexity: O(1)
  public init() {
    self._tree = ARTree<Value>()
  }
}

// MARK: Accessing Keys and Values
@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension RadixTree {
  /// Returns the value associated with the key.
  ///
  /// - Parameter key: The key to search for
  /// - Returns: `nil` if the key was not present. Otherwise, the previous value.
  /// - Complexity: O(`k`) where `k` is size of the key.
  public func getValue(forKey key: Key) -> Value? {
    key.withUnsafeBinaryComparableBytes { _tree.getValue(keyBytes: $0) }
  }
}

// MARK: Mutations
@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension RadixTree {
  /// Updates the value stored in the tree for the given key, or adds a new key-value pair if the
  /// key does not exist.
  ///
  /// Use this method instead of key-based subscripting when you need to know whether the new value
  /// supplants the value of an existing key. If the value of an existing key is updated,
  /// `updateValue(_:forKey:)` returns the original value.
  ///
  /// - Parameters:
  ///   - value: The new value to add to the tree.
  ///   - key: The key to associate with value. If key already exists in the tree, value replaces
  ///       the existing associated value. Inserts `(key, value)` otherwise.
  /// - Returns: The value that was replaced, or nil if a new key-value pair was added.
  /// - Complexity: O(`log n`) where `n` is the number of key-value pairs in the dictionary.
  public mutating func updateValue(_ value: Value, forKey key: Key) -> Bool {
    key.withUnsafeBinaryComparableBytes { _tree.insert(keyBytes: $0, value: value) }
  }
}

// MARK: Removing Keys and Values
@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension RadixTree {
  /// Removes the given key and its associated value from the tree.
  ///
  /// Calling this method invalidates any existing indices for use with this tree.
  ///
  /// - Parameter key: The key to remove along with its associated value.
  /// - Returns: The value that was removed, or `nil` if the key was not present.
  /// - Complexity: O(`log n`) where `n` is the number of key-value pairs in the collection.
  public mutating func removeValue(forKey key: Key) {
    key.withUnsafeBinaryComparableBytes { _tree.delete(keyBytes: $0) }
  }
}
