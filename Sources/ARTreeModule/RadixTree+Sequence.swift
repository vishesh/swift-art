@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension RadixTree: Sequence {
  public struct Iterator: IteratorProtocol {
    public typealias Element = (Key, Value)

    var _iter: ARTree<Value>.Iterator

    mutating public func next() -> Element? {
      guard let leaf = _iter.nextLeaf() else { return nil }
      // Decode the key straight from the leaf's bytes (no per-element [UInt8])
      // and read the value in the same pass over the leaf storage.
      return leaf.withKeyValue { keyPtr, valuePtr in
        (Key.fromBinaryComparableBytes(UnsafeRawBufferPointer(keyPtr)), valuePtr.pointee)
      }
    }
  }

  public func makeIterator() -> Iterator {
    return Iterator(_iter: _tree.makeIterator())
  }
}
