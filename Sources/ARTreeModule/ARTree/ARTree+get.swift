@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension ARTreeImpl {
  public func getValue(key: Key) -> Value? {
    key.withUnsafeBytes { getValue(keyBytes: $0) }
  }

  public func getValue(keyBytes key: UnsafeRawBufferPointer) -> Value? {
    var current = _root
    var depth = 0
    while depth <= key.count {
      guard let rawNode = current else {
        return nil
      }

      // Switch on the concrete node type so the per-hop work (prefix check, child
      // search, header reads) is specialized and inlined instead of dispatched
      // through an `any InternalNode` witness table.
      switch rawNode.type {
      case .leaf:
        let leaf = NodeLeaf<Spec>(buffer: rawNode.buf)
        return leaf.keyEquals(with: key) ? leaf.value : nil
      case .node4:
        current = _descend(Node4<Spec>(buffer: rawNode.buf), key, &depth)
      case .node16:
        current = _descend(Node16<Spec>(buffer: rawNode.buf), key, &depth)
      case .node48:
        current = _descend(Node48<Spec>(buffer: rawNode.buf), key, &depth)
      case .node256:
        current = _descend(Node256<Spec>(buffer: rawNode.buf), key, &depth)
      }
    }

    return nil
  }

  // One step down an internal node: returns the child to visit next, or nil if
  // the key is absent (prefix mismatch or no matching child). A mismatch maps to
  // `current = nil`, which the loop's guard turns into "not found".
  @inline(__always)
  private func _descend<N: InternalNode<Spec>>(
    _ node: N, _ key: UnsafeRawBufferPointer, _ depth: inout Int
  ) -> RawNode? {
    let partialLength = node.partialLength
    if partialLength > 0 {
      let prefixLen = node.prefixMismatch(withKey: key, fromIndex: depth)
      assert(prefixLen <= Const.maxPartialLength, "partial length is always bounded")
      if prefixLen != partialLength {
        return nil
      }
      depth += partialLength
    }

    let child = node.child(forKey: key[depth])
    depth += 1
    return child
  }

  public mutating func getRange(start: Key, end: Key) {
    // TODO
    fatalError("not implemented")
  }
}
