// A traversal-stack level: an internal node and its child cursor. A struct (not a
// tuple) so the cursor advances in place without retaining/releasing the node.
private struct _IterFrame {
  let node: RawNode
  var index: Int
}

@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension ARTreeImpl: Sequence {
  public typealias Iterator = _Iterator

  public struct _Iterator {
    private let tree: ARTreeImpl<Spec>
    // Concrete `RawNode` frames (not `any InternalNode`) so per-step work
    // specializes per node type instead of dispatching through a witness table.
    private var path: [_IterFrame]
    // Set when the whole tree is a single leaf (deletes can collapse the root to a
    // bare leaf). Yielded once, then cleared.
    private var rootLeaf: NodeLeaf<Spec>?

    init(tree: ARTreeImpl<Spec>) {
      self.tree = tree
      self.path = []
      self.rootLeaf = nil
      guard let node = tree._root else { return }

      if node.type == .leaf {
        self.rootLeaf = node.toLeafNode()
        return
      }
      let start = Self._startIndex(node)
      if start < Self._endIndex(node) {
        self.path = [_IterFrame(node: node, index: start)]
      }
    }
  }

  public func makeIterator() -> Iterator {
    return Iterator(tree: self)
  }
}

@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension ARTreeImpl._Iterator: IteratorProtocol {
  public typealias Element = (Key, Spec.Value)  // TODO: Why just Value fails?

  // Per-step primitives dispatched on concrete node type. `tree` keeps every node
  // alive, so wrapping `node.buf` is unretained.
  @inline(__always)
  static func _startIndex(_ node: RawNode) -> Int {
    switch node.type {
    case .node4: return Node4<Spec>(buffer: node.buf).startIndex
    case .node16: return Node16<Spec>(buffer: node.buf).startIndex
    case .node48: return Node48<Spec>(buffer: node.buf).startIndex
    case .node256: return Node256<Spec>(buffer: node.buf).startIndex
    case .leaf: return 0
    }
  }

  @inline(__always)
  static func _endIndex(_ node: RawNode) -> Int {
    switch node.type {
    case .node4: return Node4<Spec>(buffer: node.buf).endIndex
    case .node16: return Node16<Spec>(buffer: node.buf).endIndex
    case .node48: return Node48<Spec>(buffer: node.buf).endIndex
    case .node256: return Node256<Spec>(buffer: node.buf).endIndex
    case .leaf: return 0
    }
  }

  @inline(__always)
  static func _indexAfter(_ node: RawNode, _ index: Int) -> Int {
    switch node.type {
    case .node4: return Node4<Spec>(buffer: node.buf).index(after: index)
    case .node16: return Node16<Spec>(buffer: node.buf).index(after: index)
    case .node48: return Node48<Spec>(buffer: node.buf).index(after: index)
    case .node256: return Node256<Spec>(buffer: node.buf).index(after: index)
    case .leaf: return index + 1
    }
  }

  @inline(__always)
  static func _childAt(_ node: RawNode, _ index: Int) -> RawNode? {
    switch node.type {
    case .node4: return Node4<Spec>(buffer: node.buf).child(at: index)
    case .node16: return Node16<Spec>(buffer: node.buf).child(at: index)
    case .node48: return Node48<Spec>(buffer: node.buf).child(at: index)
    case .node256: return Node256<Spec>(buffer: node.buf).child(at: index)
    case .leaf: return nil
    }
  }

  mutating func next() -> Element? {
    guard let leaf = nextLeaf() else { return nil }
    return (leaf.key, leaf.value)
  }

  // Next leaf in order, without materializing its key. The public iterator
  // decodes the key from the leaf bytes; `next()` above keeps the array form.
  mutating func nextLeaf() -> NodeLeaf<Spec>? {
    if let leaf = rootLeaf {
      rootLeaf = nil
      return leaf
    }

    while let top = path.last {
      let node = top.node
      let index = top.index
      if index >= Self._endIndex(node) {
        // Exhausted this node: drop it and step the parent's cursor forward.
        path.removeLast()
        if !path.isEmpty {
          let parent = path[path.count - 1].node
          path[path.count - 1].index = Self._indexAfter(parent, path[path.count - 1].index)
        }
        continue
      }

      let child = Self._childAt(node, index)!
      if child.type == .leaf {
        let leaf: NodeLeaf<Spec> = child.toLeafNode()
        path[path.count - 1].index = Self._indexAfter(node, index)
        return leaf
      }

      path.append(_IterFrame(node: child, index: Self._startIndex(child)))
    }

    return nil
  }
}
