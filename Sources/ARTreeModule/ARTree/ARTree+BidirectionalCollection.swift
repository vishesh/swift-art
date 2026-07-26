// MARK: BidirectionalCollection conformance

@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension ARTreeImpl: BidirectionalCollection {
  // Element type must match what's in Sequence (tuple without labels)
  public typealias Element = (Key, Value)
  public typealias SubSequence = Slice<ARTreeImpl>

  public var count: Int {
    var count = 0
    for _ in self { count += 1 }
    return count
  }

  public var isEmpty: Bool {
    _root == nil
  }

  public subscript(position: Index) -> Element {
    guard let current = position.current else {
      preconditionFailure("Index out of bounds")
    }

    if current.type == .leaf {
      let leaf: NodeLeaf<Spec> = current.rawNode.toLeafNode()
      return (leaf.key, leaf.value)  // No labels to match Sequence Element type
    }

    preconditionFailure("Index not at a leaf")
  }

  public func index(after i: Index) -> Index {
    var next = i
    next.advance()
    return next
  }

  public func index(before i: Index) -> Index {
    var prev = i
    prev.retreat()
    return prev
  }
}

@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension ARTreeImpl.Index {
  // Advance to the next leaf in order
  mutating func advance() {
    if isOnLeaf {
      // Move to the next sibling
      ascendToNextBranch()
    } else if let current = current {
      // Descend to the leftmost child
      let node: any InternalNode<Spec> = current.rawNode.toInternalNode()
      descend { _ in node.startIndex }
      descentToLeftMostChild()
    }
  }

  // Retreat to the previous leaf in order
  mutating func retreat() {
    if path.isEmpty {
      // At the beginning, can't go back
      current = nil
      return
    }

    // Pop the current position and try to go to previous sibling
    guard let (parent, childIndex) = path.popLast() else {
      current = nil
      return
    }

    if let prevIndex = parent.index(before: childIndex) {
      // Move to previous sibling
      path.append((parent, prevIndex))
      if let child = parent.child(at: prevIndex) {
        current = child.toARTNode()
        // Descend to rightmost leaf of this subtree
        descendToRightMostChild()
      }
    } else {
      // No previous sibling, continue ascending
      current = parent.rawNode.toARTNode()
      retreat()
    }
  }

  // Ascend until we find a node with a next sibling
  private mutating func ascendToNextBranch() {
    while !path.isEmpty {
      let (parent, childIndex) = path.removeLast()
      let nextIndex = parent.index(after: childIndex)

      if nextIndex != parent.endIndex {
        // Found a next sibling
        path.append((parent, nextIndex))
        if let child = parent.child(at: nextIndex) {
          current = child.toARTNode()
          descentToLeftMostChild()
          return
        }
      }
      // Continue ascending
      current = parent.rawNode.toARTNode()
    }

    // Reached the end
    current = nil
  }

  // Descend to the rightmost leaf
  mutating func descendToRightMostChild() {
    while !isOnLeaf {
      let node: any InternalNode<Spec> = current!.rawNode.toInternalNode()
      // Find the last valid index
      var lastIndex = node.startIndex
      var idx = node.startIndex
      let end = node.endIndex

      while idx != end {
        if node.child(at: idx) != nil {
          lastIndex = idx
        }
        idx = node.index(after: idx)
      }

      descend { _ in lastIndex }
    }
  }
}

