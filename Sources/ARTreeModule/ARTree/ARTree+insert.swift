@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension ARTreeImpl {
  fileprivate enum InsertAction {
    case replace(NodeLeaf<Spec>)
    case splitLeaf(NodeLeaf<Spec>, depth: Int)
    case splitNode(RawNode, depth: Int, prefixDiff: Int)
    case insertInto(RawNode, depth: Int)
  }

  @discardableResult
  public mutating func insert(key: Key, value: Value) -> Bool {
    key.withUnsafeBytes { insert(keyBytes: $0, value: value) }
  }

  @discardableResult
  public mutating func insert(keyBytes key: UnsafeRawBufferPointer, value: Value) -> Bool {
    guard case (let action, var ref)? = _findInsertNode(keyBytes: key) else { return false }

    switch action {
    case .replace(let leaf):
      leaf.withValue {
        $0.pointee = value
      }

    case .splitLeaf(let leaf, let depth):
      let newLeaf = Self.allocateLeaf(keyBytes: key, value: value)
      var longestPrefix = newLeaf.read {
        leaf.longestCommonPrefix(with: $0, fromIndex: depth)
      }

      var newNode = Node4<Spec>.allocate()
      let existingByte = leaf.withKey { $0[depth + longestPrefix] }
      _ = newNode.addChild(forKey: existingByte, node: leaf)
      _ = newNode.addChild(forKey: key[depth + longestPrefix], node: newLeaf)

      // TODO: Flip the direction of node creation.
      // TODO: Optimization: Just set partialLength = longestPrefix, and look at minimum leaf for
      //    rest of the bytes (at-least until we are storing entire keys inside the leaf).
      //    Probably useful for cases where nodes share significantly long common prefix.
      while longestPrefix > 0 {
        let nBytes = Swift.min(Const.maxPartialLength, longestPrefix)
        let start = depth + longestPrefix - nBytes
        newNode.partialLength = nBytes
        newNode.partialBytes.copy(src: key, start: start, count: nBytes)
        longestPrefix -= nBytes

        if longestPrefix <= 0 {
          break
        }

        var next = Node4<Spec>.allocate()
        _ = next.addChild(forKey: key[start - 1], node: newNode)
        newNode = next
        longestPrefix -= 1  // One keys goes for mapping the child in next node.
      }

      ref.pointee = newNode.rawNode  // Replace child in parent.

    case .splitNode(let rawNode, let depth, let prefixDiff):
      let partialBytes = Self._partialBytes(rawNode)
      var newNode = Node4<Spec>.allocate()
      newNode.partialLength = prefixDiff
      newNode.partialBytes = partialBytes  // TODO: Just copy min(maxPartialLength, prefixDiff)

      assert(
        Self._partialLength(rawNode) <= Const.maxPartialLength,
        "partial length is always bounded")
      _ = newNode.addChild(forKey: partialBytes[prefixDiff], node: rawNode)
      Self._dropPrefix(rawNode, through: prefixDiff)

      let newLeaf = Self.allocateLeaf(keyBytes: key, value: value)
      _ = newNode.addChild(forKey: key[depth + prefixDiff], node: newLeaf)
      ref.pointee = newNode.rawNode

    case .insertInto(let rawNode, let depth):
      let newLeaf = Self.allocateLeaf(keyBytes: key, value: value)
      newLeaf.read { leaf in
        if case .replaceWith(let newNode) = Self._addChild(
          to: rawNode, forKey: key[depth], node: leaf.rawNode)
        {
          ref.pointee = newNode
        }
      }
    }

    return true
  }

  // TODO: Make sure that the node returned have
  fileprivate mutating func _findInsertNode(keyBytes key: UnsafeRawBufferPointer)
    -> (InsertAction, NodeReference)?
  {
    if _root == nil {
      // NOTE: Should we just create leaf? Likely tree will have more items anyway.
      _root = Node4<Spec>.allocate().read { $0.rawNode }
    }

    var depth = 0
    // Check uniqueness before binding `current` — it adds a second ref to the
    // root buffer, which would otherwise make a unique root look shared.
    var isUnique = isKnownUniquelyReferenced(&_root!.buf)
    var current: RawNode = _root!
    var ref = NodeReference(&_root)

    while current.type != .leaf && depth < key.count {
      assert(
        !Const.testCheckUnique || isUnique,
        "unique path is expected in this test, depth=\(depth)")

      if !isUnique {
        // Clone the shared node and splice the copy in before mutating it.
        let clone = current.clone(spec: Spec.self)
        ref.pointee = clone
        current = clone
      }

      let step: _InsertStep
      switch current.type {
      case .node4: step = _insertStep(Node4<Spec>(buffer: current.buf), key, &depth, &ref)
      case .node16: step = _insertStep(Node16<Spec>(buffer: current.buf), key, &depth, &ref)
      case .node48: step = _insertStep(Node48<Spec>(buffer: current.buf), key, &depth, &ref)
      case .node256: step = _insertStep(Node256<Spec>(buffer: current.buf), key, &depth, &ref)
      case .leaf: preconditionFailure("leaf handled by loop condition")
      }

      switch step {
      case .splitNode(let prefixDiff):
        return (.splitNode(current, depth: depth, prefixDiff: prefixDiff), ref)
      case .insertInto:
        return (.insertInto(current, depth: depth), ref)
      case .descend(let child, let childUnique):
        depth += 1
        current = child
        isUnique = childUnique
      }
    }

    assert(current.type == .leaf)
    // Reached leaf already, replace it with a new node, or update the existing value.
    if current.type == .leaf {
      assert(
        !Const.testCheckUnique || isUnique,
        "unique path is expected in this test, depth=\(depth)")

      let leaf: NodeLeaf<Spec> = current.toLeafNode()
      if leaf.keyEquals(with: key) {
        if isUnique {
          return (.replace(leaf), ref)
        } else {
          let clone = leaf.clone()
          ref.pointee = clone.node.rawNode
          return (.replace(clone.node), ref)
        }
      }

      if isUnique {
        return (.splitLeaf(leaf, depth: depth), ref)
      } else {
        let clone = leaf.clone()
        ref.pointee = clone.node.rawNode
        return (.splitLeaf(clone.node, depth: depth), ref)
      }
    }

    fatalError("unexpected state")
  }

  private enum _InsertStep {
    case splitNode(prefixDiff: Int)
    case insertInto
    case descend(child: RawNode, childUnique: Bool)
  }

  private func _insertStep<N: InternalNode<Spec>>(
    _ node: N,
    _ key: UnsafeRawBufferPointer,
    _ depth: inout Int,
    _ ref: inout NodeReference
  ) -> _InsertStep {
    var node = node
    if node.partialLength > 0 {
      let partialLength = node.partialLength
      let prefixDiff = node.prefixMismatch(withKey: key, fromIndex: depth)
      if prefixDiff >= partialLength {
        depth += partialLength
      } else {
        return .splitNode(prefixDiff: prefixDiff)
      }
    }

    guard let index = node.index(forKey: key[depth]) else {
      return .insertInto
    }

    return node.withChildRef(at: index) { ptr in
      ref = NodeReference(ptr)
      // Check uniqueness in place; a copied-out child would add a second ref.
      let childUnique = ptr.pointee!.isUnique
      return .descend(child: ptr.pointee!, childUnique: childUnique)
    }
  }
}

extension ARTreeImpl {
  static func allocateLeaf(key: Key, value: Value) -> NodeStorage<NodeLeaf<Spec>> {
    return NodeLeaf<Spec>.allocate(key: key, value: value)
  }

  static func allocateLeaf(keyBytes key: UnsafeRawBufferPointer, value: Value)
    -> NodeStorage<NodeLeaf<Spec>>
  {
    return NodeLeaf<Spec>.allocate(keyBytes: key, value: value)
  }

  @inline(__always)
  private static func _partialLength(_ rawNode: RawNode) -> Int {
    switch rawNode.type {
    case .node4: return Node4<Spec>(buffer: rawNode.buf).partialLength
    case .node16: return Node16<Spec>(buffer: rawNode.buf).partialLength
    case .node48: return Node48<Spec>(buffer: rawNode.buf).partialLength
    case .node256: return Node256<Spec>(buffer: rawNode.buf).partialLength
    case .leaf: preconditionFailure("leaf nodes have no internal prefix")
    }
  }

  @inline(__always)
  private static func _partialBytes(_ rawNode: RawNode) -> PartialBytes {
    switch rawNode.type {
    case .node4: return Node4<Spec>(buffer: rawNode.buf).partialBytes
    case .node16: return Node16<Spec>(buffer: rawNode.buf).partialBytes
    case .node48: return Node48<Spec>(buffer: rawNode.buf).partialBytes
    case .node256: return Node256<Spec>(buffer: rawNode.buf).partialBytes
    case .leaf: preconditionFailure("leaf nodes have no internal prefix")
    }
  }

  @inline(__always)
  private static func _dropPrefix(_ rawNode: RawNode, through prefixDiff: Int) {
    switch rawNode.type {
    case .node4:
      var node = Node4<Spec>(buffer: rawNode.buf)
      node.partialBytes.shiftLeft(toIndex: prefixDiff + 1)
      node.partialLength -= prefixDiff + 1
    case .node16:
      var node = Node16<Spec>(buffer: rawNode.buf)
      node.partialBytes.shiftLeft(toIndex: prefixDiff + 1)
      node.partialLength -= prefixDiff + 1
    case .node48:
      var node = Node48<Spec>(buffer: rawNode.buf)
      node.partialBytes.shiftLeft(toIndex: prefixDiff + 1)
      node.partialLength -= prefixDiff + 1
    case .node256:
      var node = Node256<Spec>(buffer: rawNode.buf)
      node.partialBytes.shiftLeft(toIndex: prefixDiff + 1)
      node.partialLength -= prefixDiff + 1
    case .leaf:
      preconditionFailure("leaf nodes have no internal prefix")
    }
  }

  @inline(__always)
  private static func _addChild(to rawNode: RawNode, forKey key: KeyPart, node child: RawNode)
    -> UpdateResult<RawNode?>
  {
    switch rawNode.type {
    case .node4:
      var node = Node4<Spec>(buffer: rawNode.buf)
      return node.addChild(forKey: key, node: child)
    case .node16:
      var node = Node16<Spec>(buffer: rawNode.buf)
      return node.addChild(forKey: key, node: child)
    case .node48:
      var node = Node48<Spec>(buffer: rawNode.buf)
      return node.addChild(forKey: key, node: child)
    case .node256:
      var node = Node256<Spec>(buffer: rawNode.buf)
      return node.addChild(forKey: key, node: child)
    case .leaf:
      preconditionFailure("leaf nodes cannot accept children")
    }
  }
}
