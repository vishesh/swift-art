// Prefix scan. Descend O(prefix length) to the single subtree whose keys all
// begin with the search prefix, then emit that subtree wholesale — no per-leaf
// prefix re-check, and no dependence on tree size beyond the descent.

@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension ARTreeImpl {
  // Visit every (keyBytes, value) whose key starts with `prefix`, ascending.
  // `keyBytes` is valid only for the duration of the `body` call.
  func forEachWithPrefix(
    _ prefix: UnsafeRawBufferPointer,
    _ body: (UnsafeRawBufferPointer, Value) -> Void
  ) {
    guard let root = _root else { return }
    withExtendedLifetime(root.buf) {
      _ = _prefixVisit(root, prefix, depth: 0) {
        body($0, $1)
        return true
      }
    }
  }

  private func _prefixVisit(
    _ node: RawNode, _ prefix: UnsafeRawBufferPointer, depth: Int,
    _ body: (UnsafeRawBufferPointer, Value) -> Bool
  ) -> Bool {
    // The whole prefix is matched by the path down to here: everything below matches.
    if depth >= prefix.count { return _emitSubtree(node, body) }

    if node.type == .leaf {
      let leaf = NodeLeaf<Spec>(buffer: node.buf)
      return leaf.withKeyValue { keyPtr, valuePtr in
        let key = UnsafeRawBufferPointer(keyPtr)
        if key.count < prefix.count { return true }
        var i = depth
        while i < prefix.count {
          if key[i] != prefix[i] { return true }
          i += 1
        }
        return body(key, valuePtr.pointee)
      }
    }

    let inode: any InternalNode<Spec> = node.toInternalNode()
    var depth = depth

    let partialLength = inode.partialLength
    if partialLength > 0 {
      let partial = inode.partialBytes
      for i in 0..<partialLength {
        // Prefix ends inside this node's partial and matched so far ⇒ all below match.
        if depth >= prefix.count { return _emitSubtree(node, body) }
        if partial[i] != prefix[depth] { return true }  // divergence ⇒ no matches here
        depth += 1
      }
    }

    if depth >= prefix.count { return _emitSubtree(node, body) }

    guard let idx = inode.index(forKey: prefix[depth]),
      let child = inode.child(at: idx)
    else {
      return true
    }
    return _prefixVisit(child, prefix, depth: depth + 1, body)
  }
}
