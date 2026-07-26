// MARK: Mutation operations

@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension RadixTree {
  /// Removes and returns the first element of the tree.
  ///
  /// - Returns: The first key-value pair if the tree is non-empty, nil otherwise
  /// - Complexity: O(log n)
  @discardableResult
  public mutating func popFirst() -> Element? {
    guard !isEmpty else { return nil }

    let first = self.first!
    removeValue(forKey: first.0)
    return first
  }

  /// Removes and returns the last element of the tree.
  ///
  /// - Returns: The last key-value pair if the tree is non-empty, nil otherwise
  /// - Complexity: O(log n)
  @discardableResult
  public mutating func popLast() -> Element? {
    guard !isEmpty else { return nil }

    let last = self.last!
    removeValue(forKey: last.0)
    return last
  }

  /// Removes and returns the first element of the tree.
  ///
  /// The tree must not be empty.
  ///
  /// - Returns: The first key-value pair
  /// - Complexity: O(log n)
  @discardableResult
  public mutating func removeFirst() -> Element {
    guard let first = popFirst() else {
      preconditionFailure("Cannot remove first element from an empty tree")
    }
    return first
  }

  /// Removes and returns the last element of the tree.
  ///
  /// The tree must not be empty.
  ///
  /// - Returns: The last key-value pair
  /// - Complexity: O(log n)
  @discardableResult
  public mutating func removeLast() -> Element {
    guard let last = popLast() else {
      preconditionFailure("Cannot remove last element from an empty tree")
    }
    return last
  }

  /// Removes the specified number of elements from the beginning of the tree.
  ///
  /// - Parameter k: The number of elements to remove. Must be non-negative.
  /// - Complexity: O(k * log n)
  public mutating func removeFirst(_ k: Int) {
    precondition(k >= 0, "Can't remove a negative number of elements")
    precondition(k <= count, "Can't remove more elements than the tree contains")

    for _ in 0..<k {
      _ = removeFirst()
    }
  }

  /// Removes the specified number of elements from the end of the tree.
  ///
  /// - Parameter k: The number of elements to remove. Must be non-negative.
  /// - Complexity: O(k * log n)
  public mutating func removeLast(_ k: Int) {
    precondition(k >= 0, "Can't remove a negative number of elements")
    precondition(k <= count, "Can't remove more elements than the tree contains")

    for _ in 0..<k {
      _ = removeLast()
    }
  }

  /// Removes all elements from the tree.
  ///
  /// - Complexity: O(1)
  public mutating func removeAll() {
    _tree = ARTreeImpl()
  }

  /// Removes all elements from the tree, optionally keeping the allocated capacity.
  ///
  /// - Parameter keepCapacity: Ignored for tree structures (included for API compatibility)
  /// - Complexity: O(1)
  public mutating func removeAll(keepingCapacity keepCapacity: Bool) {
    // Tree structures don't have a meaningful concept of capacity to preserve
    removeAll()
  }


  /// Modifies the value for a key, inserting a default value if the key doesn't exist.
  ///
  /// This method is useful when you need to perform in-place mutations on values or
  /// when the closure needs to return a result.
  ///
  /// ```swift
  /// let newCount = tree.modifyValue(forKey: "apple", default: 0) { count in
  ///   count += 1
  ///   return count
  /// }
  /// ```
  ///
  /// - Parameters:
  ///   - key: The key whose value should be modified
  ///   - defaultValue: The value to insert if the key doesn't exist
  ///   - body: A closure that modifies the value and optionally returns a result
  /// - Returns: The result of the body closure
  /// - Throws: Rethrows any error thrown by the body closure
  public mutating func modifyValue<R>(
    forKey key: Key,
    default defaultValue: @autoclosure () -> Value,
    _ body: (inout Value) throws -> R
  ) rethrows -> R {
    // Ensure the key exists with default value if needed
    if self[key] == nil {
      self[key] = defaultValue()
    }

    // Modify the value and capture the result
    var value = self[key]!
    defer { self[key] = value }
    return try body(&value)
  }

  /// Checks whether the tree contains the given key.
  ///
  /// - Parameter key: The key to search for
  /// - Returns: true if the key exists in the tree, false otherwise
  /// - Complexity: O(k) where k is the key length
  public func contains(key: Key) -> Bool {
    self[key] != nil
  }

  /// Returns the index for the given key if it exists in the tree.
  ///
  /// - Parameter key: The key to search for
  /// - Returns: The index of the key-value pair, or nil if the key doesn't exist
  /// - Complexity: O(k + log n) where k is the key length
  public func index(forKey key: Key) -> Index? where Key: Equatable {
    // This is a naive implementation - could be optimized
    var idx = startIndex
    while idx != endIndex {
      if self[idx].0 == key {
        return idx
      }
      idx = index(after: idx)
    }
    return nil
  }
}

// MARK: ARTree-specific mutations (for byte array keys)

@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension ARTreeImpl {
  /// Removes all elements from the tree.
  ///
  /// - Complexity: O(1)
  public mutating func removeAll() {
    _root = nil
    version += 1
  }

  /// Checks whether the tree contains the given key.
  ///
  /// - Parameter key: The key to search for
  /// - Returns: true if the key exists in the tree, false otherwise
  /// - Complexity: O(k) where k is the key length
  public func contains(key: Key) -> Bool {
    getValue(key: key) != nil
  }
}