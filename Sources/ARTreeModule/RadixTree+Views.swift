// MARK: Keys and Values views

@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension RadixTree {
  /// A view of a tree's keys.
  public struct Keys: Collection, BidirectionalCollection {
    private let _tree: RadixTree

    fileprivate init(_ tree: RadixTree) {
      self._tree = tree
    }

    public typealias Element = Key
    public typealias Index = RadixTree.Index

    public var startIndex: Index { _tree.startIndex }
    public var endIndex: Index { _tree.endIndex }
    public var count: Int { _tree.count }
    public var isEmpty: Bool { _tree.isEmpty }

    public subscript(position: Index) -> Key {
      _tree[position].0  // First element of tuple
    }

    public func index(after i: Index) -> Index {
      _tree.index(after: i)
    }

    public func index(before i: Index) -> Index {
      _tree.index(before: i)
    }

    public func contains(_ key: Key) -> Bool {
      _tree.contains(key: key)
    }

    public var first: Key? {
      _tree.first?.0
    }

    public var last: Key? {
      _tree.last?.0
    }
  }

  /// A view of a tree's values.
  public struct Values: MutableCollection, BidirectionalCollection {
    private var _tree: RadixTree

    fileprivate init(_ tree: RadixTree) {
      self._tree = tree
    }

    public typealias Element = Value
    public typealias Index = RadixTree.Index

    public var startIndex: Index { _tree.startIndex }
    public var endIndex: Index { _tree.endIndex }
    public var count: Int { _tree.count }
    public var isEmpty: Bool { _tree.isEmpty }

    public subscript(position: Index) -> Value {
      get {
        _tree[position].1  // Second element of tuple
      }
      set {
        // This is tricky - we need to update the value at this index
        // We'll need to get the key first, then update
        let key = _tree[position].0
        _tree[key] = newValue
      }
    }

    public func index(after i: Index) -> Index {
      _tree.index(after: i)
    }

    public func index(before i: Index) -> Index {
      _tree.index(before: i)
    }

    public var first: Value? {
      _tree.first?.1
    }

    public var last: Value? {
      _tree.last?.1
    }

    // Mutating operations
    public mutating func modifyEach(_ body: (inout Value) throws -> Void) rethrows {
      // Collect keys first to avoid exclusivity violation
      let keys = Array(_tree.keys)
      for key in keys {
        if let currentValue = _tree[key] {
          try _tree.modifyValue(forKey: key, default: currentValue) { value in
            try body(&value)
          }
        }
      }
    }
  }

  /// A collection containing just the keys of the tree.
  ///
  /// When iterated over, keys appear in this collection in the same order as
  /// they occur in the tree's key-value pairs.
  ///
  /// ```swift
  /// let tree: RadixTree = ["a": 1, "b": 2, "c": 3]
  /// for key in tree.keys {
  ///   print(key)
  /// }
  /// // Prints "a", "b", "c" in sorted order
  /// ```
  public var keys: Keys {
    Keys(self)
  }

  /// A mutable collection containing just the values of the tree.
  ///
  /// When iterated over, values appear in this collection in the same order as
  /// they occur in the tree's key-value pairs.
  ///
  /// ```swift
  /// var tree: RadixTree = ["a": 1, "b": 2, "c": 3]
  /// for i in tree.values.indices {
  ///   tree.values[i] *= 2
  /// }
  /// // tree is now ["a": 2, "b": 4, "c": 6]
  /// ```
  public var values: Values {
    get {
      Values(self)
    }
    set {
      // Replace all values with those from the new collection
      var newValuesIterator = newValue.makeIterator()
      for key in self.keys {
        guard let nextValue = newValuesIterator.next() else {
          preconditionFailure("Not enough values provided")
        }
        self[key] = nextValue
      }

      if newValuesIterator.next() != nil {
        preconditionFailure("Too many values provided")
      }
    }
  }
}