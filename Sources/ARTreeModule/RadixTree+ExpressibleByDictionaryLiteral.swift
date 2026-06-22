@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension RadixTree: ExpressibleByDictionaryLiteral {
  /// Creates a new Radix Tree from the contents of a dictionary
  /// literal.
  ///
  /// Duplicate elements in the literal are allowed, but the resulting
  /// set will only contain the last occurrence of each.
  ///
  /// Do not call this initializer directly. It is used by the compiler when you
  /// use a dictionary literal. Instead, create a new ordered dictionary using a
  /// dictionary literal as its value by enclosing a comma-separated list of
  /// values in square brackets. You can use an array literal anywhere a set is
  /// expected by the type context.
  ///
  /// - Parameter elements: A variadic list of key-value pairs for the new
  ///    dictionary.
  ///
  /// - Complexity: O(n * k), where n is the number of key-value pairs and k is key length.
  @inlinable
  public init(dictionaryLiteral elements: (Key, Value)...) {
    self.init(keysWithValues: elements)
  }
}
