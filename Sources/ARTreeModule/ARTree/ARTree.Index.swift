@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension ARTreeImpl {
  public struct Index {
    internal typealias _ChildIndex = InternalNode<Spec>.Index

    internal weak var root: RawNodeBuffer? = nil
    internal var current: (any ARTNode<Spec>)? = nil
    internal var path: [(any InternalNode<Spec>, _ChildIndex)] = []
    internal let version: Int

    internal init(forTree tree: ARTreeImpl<Spec>) {
      self.version = tree.version

      if let root = tree._root {
        // A single-leaf root is possible after deletes collapse the tree. The
        // Sequence iterator handles it; this index-based path is not yet wired for
        // a leaf root (no Collection conformance uses it today).
        self.root = root.buf
        self.current = root.toARTNode()
      }
    }
  }
}

@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension ARTreeImpl.Index {
  internal var isOnLeaf: Bool {
    if let current = self.current {
      return current.type == .leaf
    }

    return false
  }

  internal mutating func descentToLeftMostChild() {
    while !isOnLeaf {
      descend { $0.startIndex }
    }
  }

  internal mutating func descend(_ to: (any InternalNode<Spec>)
                                   -> (any InternalNode<Spec>).Index) {
    assert(!isOnLeaf, "can't descent on a leaf node")
    assert(current != nil, "current node can't be nil")

    let currentNode: any InternalNode<Spec> = current!.rawNode.toInternalNode()
    let index = to(currentNode)
    self.path.append((currentNode, index))
    self.current = currentNode.child(at: index)?.toARTNode()
  }

  mutating private func advanceToSibling() {
    let _ = path.popLast()
    advanceToNextChild()
  }

  mutating private func advanceToNextChild() {
    guard let (node, index) = path.popLast() else {
      return
    }

    path.append((node, node.index(after: index)))
  }
}


@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension ARTreeImpl.Index: Equatable {
  @usableFromInline
  static func == (lhs: Self, rhs: Self) -> Bool {
    // First check if both have the same current node
    if case (let lhsNode?, let rhsNode?) = (lhs.current, rhs.current) {
      // Check if nodes are equal
      return lhsNode.equals(rhsNode)
    }

    return lhs.current == nil && rhs.current == nil
  }
}

@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension ARTreeImpl.Index: Comparable {
  @usableFromInline
  static func < (lhs: Self, rhs: Self) -> Bool {
    // Compare paths first
    for ((_, idxL), (_, idxR)) in zip(lhs.path, rhs.path) {
      if idxL < idxR {
        return true
      } else if idxL > idxR {
        return false
      }
    }

    // If paths are equal but one is longer, shorter path comes first
    if lhs.path.count < rhs.path.count {
      return true
    } else if lhs.path.count > rhs.path.count {
      return false
    }

    // Same path, they are equal
    return false
  }
}
