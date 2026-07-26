// MARK: BidirectionalCollection conformance for RadixTree

@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension RadixTree: BidirectionalCollection {
  // Index needs to be exposed properly
  public struct Index: Comparable {
    @usableFromInline
    internal var _base: ARTreeImpl<DefaultSpec<Value>>.Index

    @usableFromInline
    internal init(_ base: ARTreeImpl<DefaultSpec<Value>>.Index) {
      self._base = base
    }

    public static func == (lhs: Index, rhs: Index) -> Bool {
      lhs._base == rhs._base
    }

    public static func < (lhs: Index, rhs: Index) -> Bool {
      lhs._base < rhs._base
    }
  }
  // Element must match Sequence's definition (tuple without labels)
  public typealias Element = (Key, Value)
  public typealias SubSequence = Slice<RadixTree>

  public var startIndex: Index {
    Index(_tree.startIndex)
  }

  public var endIndex: Index {
    Index(_tree.endIndex)
  }

  public var count: Int {
    _tree.count
  }

  public var isEmpty: Bool {
    _tree.isEmpty
  }

  public subscript(position: Index) -> Element {
    let element = _tree[position._base]
    return (Key.fromBinaryComparableBytes(element.0), element.1)
  }

  public func index(after i: Index) -> Index {
    Index(_tree.index(after: i._base))
  }

  public func index(before i: Index) -> Index {
    Index(_tree.index(before: i._base))
  }

  // Additional collection operations
  // Note: first and last are provided by Collection protocol default implementations
}