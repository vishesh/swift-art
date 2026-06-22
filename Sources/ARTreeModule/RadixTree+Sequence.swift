@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension RadixTree: Sequence {
  public struct Iterator: IteratorProtocol {
    public typealias Element = (Key, Value)

    var _iter: ARTree<Value>.Iterator

    mutating public func next() -> Element? {
      guard let (k, v) = _iter.next() else { return nil }
      return (Key.fromBinaryComparableBytes(k), v)
    }
  }

  public func makeIterator() -> Iterator {
    return Iterator(_iter: _tree.makeIterator())
  }
}
