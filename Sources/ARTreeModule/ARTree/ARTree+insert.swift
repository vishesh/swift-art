@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension ARTreeImpl {
  fileprivate enum InsertAction {
    case replace(NodeLeaf<Spec>)
    case splitLeaf(NodeLeaf<Spec>, depth: Int)
    case splitNode(any InternalNode<Spec>, depth: Int, prefixDiff: Int)
    case insertInto(any InternalNode<Spec>, depth: Int)
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

    case .splitNode(var node, let depth, let prefixDiff):
      var newNode = Node4<Spec>.allocate()
      newNode.partialLength = prefixDiff
      newNode.partialBytes = node.partialBytes  // TODO: Just copy min(maxPartialLength, prefixDiff)

      assert(
        node.partialLength <= Const.maxPartialLength,
        "partial length is always bounded")
      _ = newNode.addChild(forKey: node.partialBytes[prefixDiff], node: node)
      node.partialBytes.shiftLeft(toIndex: prefixDiff + 1)
      node.partialLength -= prefixDiff + 1

      let newLeaf = Self.allocateLeaf(keyBytes: key, value: value)
      _ = newNode.addChild(forKey: key[depth + prefixDiff], node: newLeaf)
      ref.pointee = newNode.rawNode

    case .insertInto(var node, let depth):
      Self.allocateLeaf(keyBytes: key, value: value).read { newLeaf in
        if case .replaceWith(let newNode) = node.addChild(forKey: key[depth], node: newLeaf) {
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
    var current: any ARTNode<Spec> = _root!.toARTNode()
    var isUnique = isKnownUniquelyReferenced(&_root!.buf)
    var ref = NodeReference(&_root)

    while current.type != .leaf && depth < key.count {
      assert(
        !Const.testCheckUnique || isUnique,
        "unique path is expected in this test, depth=\(depth)")

      if !isUnique {
        // TODO: Why making this one-liner crashes?
        let clone = current.rawNode.clone(spec: Spec.self)
        current = clone.toARTNode()
        ref.pointee = current.rawNode
      }

      var node: any InternalNode<Spec> = current.rawNode.toInternalNode()
      if node.partialLength > 0 {
        let partialLength = node.partialLength
        let prefixDiff = node.prefixMismatch(withKey: key, fromIndex: depth)
        if prefixDiff >= partialLength {
          // Matched all partial bytes. Continue to next child.
          depth += partialLength
        } else {
          // Incomplete match with partial bytes, hence needs splitting.
          return (.splitNode(node, depth: depth, prefixDiff: prefixDiff), ref)
        }
      }

      // Find next child to continue.
      guard
        let (next, _isUnique) =
          (node.maybeReadChild(forKey: key[depth], ref: &ref) { ($0, $1) })
      else {
        return (.insertInto(node, depth: depth), ref)
      }

      depth += 1
      current = next
      isUnique = _isUnique
    }

    assert(current.type == .leaf)
    // Reached leaf already, replace it with a new node, or update the existing value.
    if current.type == .leaf {
      assert(
        !Const.testCheckUnique || isUnique,
        "unique path is expected in this test, depth=\(depth)")

      let leaf: NodeLeaf<Spec> = current.rawNode.toLeafNode()
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
}
