// MARK: Subscript variants
@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension RadixTree {
  /// Accesses the value associated with the key for both read and write operations
  ///
  /// This key-based subscript returns the value for the given key if the key is found in
  /// the tree, or nil if the key is not found.
  ///
  /// When you assign a value for a key and that key already exists, the tree overwrites
  /// the existing value. If the tree doesn’t contain the key, the key and value are added
  /// as a new key-value pair.
  ///
  /// - Parameter key: The key to find in the tree
  /// - Returns: The value associated with key if key is in the tree; otherwise, nil.
  /// - Complexity: O(?)
  @inlinable
  @inline(__always)
  public subscript(key: Key) -> Value? {
    get {
      return self.getValue(forKey: key)
    }

    set {
      if let newValue = newValue {
        _ = self.updateValue(newValue, forKey: key)
      } else {
        self.removeValue(forKey: key)
      }
    }
  }

  /// Accesses the value for the given key, or returns/sets a default value if the key doesn't exist.
  ///
  /// This subscript enables patterns like counting:
  /// ```swift
  /// var counts: RadixTree<String, Int> = [:]
  /// counts["apple", default: 0] += 1
  /// ```
  ///
  /// - Parameters:
  ///   - key: The key to find in the tree
  ///   - defaultValue: The default value to return if the key doesn't exist
  /// - Returns: The value associated with key, or defaultValue if key doesn't exist
  /// - Complexity: O(k) where k is the key length
  public subscript(
    key: Key,
    default defaultValue: @autoclosure () -> Value
  ) -> Value {
    get {
      self[key] ?? defaultValue()
    }
    set {
      self[key] = newValue
    }
    _modify {
      // Get existing value or insert default
      if self[key] == nil {
        self[key] = defaultValue()
      }

      // Create accessor to the value
      var value = self[key]!
      defer { self[key] = value }
      yield &value
    }
  }

}
