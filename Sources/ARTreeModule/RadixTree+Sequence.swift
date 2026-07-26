@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension RadixTree: Sequence {
  public struct Iterator: IteratorProtocol {
    public typealias Element = (Key, Value)

    var _iter: ARTree<Value>.Iterator

    mutating public func next() -> Element? {
      // Use the public next() method which handles both single and bucket leaves
      guard let (keyBytes, value) = _iter.next() else { return nil }
      // Convert raw key bytes to the typed Key
      return (Key.fromBinaryComparableBytes(keyBytes.withUnsafeBytes { $0 }), value)
    }
  }

  public func makeIterator() -> Iterator {
    return Iterator(_iter: _tree.makeIterator())
  }
}
