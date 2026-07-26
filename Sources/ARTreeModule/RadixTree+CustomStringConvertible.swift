// MARK: CustomStringConvertible and CustomDebugStringConvertible

@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension RadixTree: CustomStringConvertible, CustomDebugStringConvertible {
  /// A textual representation of the tree.
  ///
  /// The format matches Swift's Dictionary: `[key1: value1, key2: value2, ...]`
  public var description: String {
    if isEmpty {
      return "[:]"
    }

    let items = map { "\($0.0): \($0.1)" }
    return "[\(items.joined(separator: ", "))]"
  }

  /// A textual representation of the tree, suitable for debugging.
  ///
  /// Includes the type information: `RadixTree<Key, Value>([key1: value1, ...])`
  public var debugDescription: String {
    let typeName = "RadixTree<\(Key.self), \(Value.self)>"
    if isEmpty {
      return "\(typeName)([:]))"
    }

    let items = map { "\($0.0): \($0.1)" }
    return "\(typeName)([\(items.joined(separator: ", "))])"
  }
}