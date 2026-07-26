// MARK: Transformation operations

@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension RadixTree {
  /// Returns a new tree containing the keys of this tree with the values
  /// transformed by the given closure.
  ///
  /// - Parameter transform: A closure that transforms a value. `transform`
  ///   accepts each value of the tree as its parameter and returns a
  ///   transformed value of the same or different type.
  /// - Returns: A tree containing the keys and transformed values of this tree.
  /// - Complexity: O(n) where n is the number of elements
  public func mapValues<T>(
    _ transform: (Value) throws -> T
  ) rethrows -> RadixTree<Key, T> {
    var result = RadixTree<Key, T>()

    for (key, value) in self {
      result[key] = try transform(value)
    }

    return result
  }

  /// Returns a new tree containing only the key-value pairs that have
  /// non-nil values as the result of transformation by the given closure.
  ///
  /// Use this method to transform and filter values in a single operation.
  ///
  /// - Parameter transform: A closure that transforms a value. `transform`
  ///   accepts each value of the tree as its parameter and returns an
  ///   optional transformed value.
  /// - Returns: A tree containing the keys and non-nil transformed values.
  /// - Complexity: O(n) where n is the number of elements
  public func compactMapValues<T>(
    _ transform: (Value) throws -> T?
  ) rethrows -> RadixTree<Key, T> {
    var result = RadixTree<Key, T>()

    for (key, value) in self {
      if let newValue = try transform(value) {
        result[key] = newValue
      }
    }

    return result
  }

  /// Returns a new tree containing only the key-value pairs that satisfy
  /// the given predicate.
  ///
  /// - Parameter isIncluded: A closure that takes a key-value pair as its
  ///   argument and returns a Boolean value indicating whether the pair
  ///   should be included in the returned tree.
  /// - Returns: A tree containing the key-value pairs that `isIncluded` allows.
  /// - Complexity: O(n) where n is the number of elements
  public func filter(
    _ isIncluded: (Element) throws -> Bool
  ) rethrows -> RadixTree {
    var result = RadixTree()

    for element in self {
      if try isIncluded(element) {
        result[element.0] = element.1
      }
    }

    return result
  }

  /// Returns a new tree containing the key-value pairs of the tree,
  /// sorted using the given predicate as the comparison between elements.
  ///
  /// Note: RadixTree is already sorted by key, so this method is provided
  /// mainly for API compatibility. It returns a new tree with the same contents.
  ///
  /// - Parameter areInIncreasingOrder: A predicate that returns true if its
  ///   first argument should be ordered before its second argument.
  /// - Returns: A tree with the same elements as this tree.
  /// - Complexity: O(n log n) if reordering is needed
  public func sorted(
    by areInIncreasingOrder: (Element, Element) throws -> Bool
  ) rethrows -> [Element] {
    return try Array(self).sorted(by: areInIncreasingOrder)
  }

  /// Calls the given closure on each element in the tree in order.
  ///
  /// - Parameter body: A closure that takes a key-value pair as a parameter.
  /// - Complexity: O(n) where n is the number of elements
  public func forEach(
    _ body: (Element) throws -> Void
  ) rethrows {
    for element in self {
      try body(element)
    }
  }

  /// Returns an array containing the results of mapping the given closure
  /// over the tree's elements.
  ///
  /// - Parameter transform: A mapping closure. `transform` accepts an element
  ///   of this tree as its parameter and returns a transformed value.
  /// - Returns: An array containing the transformed elements of this tree.
  /// - Complexity: O(n) where n is the number of elements
  public func map<T>(
    _ transform: (Element) throws -> T
  ) rethrows -> [T] {
    var result: [T] = []
    result.reserveCapacity(count)

    for element in self {
      result.append(try transform(element))
    }

    return result
  }

  /// Returns an array containing the non-nil results of calling the given
  /// transformation with each element of this tree.
  ///
  /// - Parameter transform: A closure that accepts an element of this tree
  ///   as its argument and returns an optional value.
  /// - Returns: An array of the non-nil results of calling `transform` with
  ///   each element of the tree.
  /// - Complexity: O(n) where n is the number of elements
  public func compactMap<T>(
    _ transform: (Element) throws -> T?
  ) rethrows -> [T] {
    var result: [T] = []

    for element in self {
      if let transformed = try transform(element) {
        result.append(transformed)
      }
    }

    return result
  }

  /// Returns the result of combining the elements of the tree using the
  /// given closure.
  ///
  /// - Parameters:
  ///   - initialResult: The value to use as the initial accumulating value.
  ///   - nextPartialResult: A closure that combines an accumulating value and
  ///     an element of the tree into a new accumulating value.
  /// - Returns: The final accumulated value.
  /// - Complexity: O(n) where n is the number of elements
  public func reduce<Result>(
    _ initialResult: Result,
    _ nextPartialResult: (Result, Element) throws -> Result
  ) rethrows -> Result {
    var result = initialResult

    for element in self {
      result = try nextPartialResult(result, element)
    }

    return result
  }

  /// Returns the result of combining the elements of the tree using the
  /// given closure.
  ///
  /// - Parameters:
  ///   - initialResult: The value to use as the initial accumulating value.
  ///   - updateAccumulatingResult: A closure that updates the accumulating value
  ///     with an element of the tree.
  /// - Returns: The final accumulated value.
  /// - Complexity: O(n) where n is the number of elements
  public func reduce<Result>(
    into initialResult: Result,
    _ updateAccumulatingResult: (inout Result, Element) throws -> Void
  ) rethrows -> Result {
    var result = initialResult

    for element in self {
      try updateAccumulatingResult(&result, element)
    }

    return result
  }

  /// Returns a Boolean value indicating whether the tree contains an element
  /// that satisfies the given predicate.
  ///
  /// - Parameter predicate: A closure that takes an element of the tree as its
  ///   argument and returns a Boolean value that indicates whether the element
  ///   satisfies the predicate.
  /// - Returns: `true` if the tree contains an element that satisfies
  ///   `predicate`; otherwise, `false`.
  /// - Complexity: O(n) where n is the number of elements
  public func contains(
    where predicate: (Element) throws -> Bool
  ) rethrows -> Bool {
    for element in self {
      if try predicate(element) {
        return true
      }
    }
    return false
  }

  /// Returns a Boolean value indicating whether every element of the tree
  /// satisfies the given predicate.
  ///
  /// - Parameter predicate: A closure that takes an element of the tree as its
  ///   argument and returns a Boolean value that indicates whether the element
  ///   satisfies the predicate.
  /// - Returns: `true` if every element satisfies `predicate`; otherwise, `false`.
  /// - Complexity: O(n) where n is the number of elements
  public func allSatisfy(
    _ predicate: (Element) throws -> Bool
  ) rethrows -> Bool {
    for element in self {
      if try !predicate(element) {
        return false
      }
    }
    return true
  }

  /// Returns the first element of the tree that satisfies the given predicate.
  ///
  /// - Parameter predicate: A closure that takes an element of the tree as its
  ///   argument and returns a Boolean value that indicates whether the element
  ///   is a match.
  /// - Returns: The first element that satisfies `predicate`, or `nil` if no
  ///   element satisfies the predicate.
  /// - Complexity: O(n) where n is the number of elements
  public func first(
    where predicate: (Element) throws -> Bool
  ) rethrows -> Element? {
    for element in self {
      if try predicate(element) {
        return element
      }
    }
    return nil
  }
}