@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension RadixTree: Sequence {
  public struct Iterator: IteratorProtocol {
    public typealias Element = (Key, Value)

    var _iter: ARTree<Value>.Iterator

    mutating public func next() -> Element? {
      guard let (keyBytes, value) = _iter.next() else { return nil }
      // `keyBytes` is `[UInt8]`; decode via the array overload. (Do NOT pass
      // `keyBytes.withUnsafeBytes { $0 }` — that escapes the buffer pointer past
      // the closure; release then reuses the storage and the key decodes to zeros.)
      return (Key.fromBinaryComparableBytes(keyBytes), value)
    }
  }

  public func makeIterator() -> Iterator {
    return Iterator(_iter: _tree.makeIterator())
  }
}
