@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension ARTreeImpl {
  /// Visit every (keyBytes, value) whose key starts with the given prefix.
  func forEachWithPrefix(
    _ prefix: UnsafeRawBufferPointer,
    _ body: (UnsafeRawBufferPointer, Value) -> Void
  ) {
    guard let root = _root else { return }
    _prefixVisit(root, prefix, 0, body)
  }

  private func _prefixVisit(
    _ node: RawNode,
    _ searchPrefix: UnsafeRawBufferPointer,
    _ depth: Int,
    _ body: (UnsafeRawBufferPointer, Value) -> Void
  ) {
    if node.type == .leaf {
      let leaf = NodeLeaf<Spec>(buffer: node.buf)
      leaf.withKeyValue { keyPtr, valuePtr in
        let key = UnsafeRawBufferPointer(keyPtr)
        // Check if key starts with searchPrefix
        if key.count >= searchPrefix.count {
          var matches = true
          for i in 0..<searchPrefix.count {
            if key[i] != searchPrefix[i] {
              matches = false
              break
            }
          }
          if matches {
            body(key, valuePtr.pointee)
          }
        }
      }
      return
    }

    let inode: any InternalNode<Spec> = node.toInternalNode()
    var newDepth = depth

    // Check if node's partial matches the search prefix
    let partialLength = inode.partialLength
    if partialLength > 0 {
      let matchBytes = inode.prefixMismatch(withKey: searchPrefix, fromIndex: depth)

      // If there's a mismatch before we match the partial completely
      if matchBytes < partialLength {
        // Check if we've at least matched the entire search prefix
        if depth + matchBytes >= searchPrefix.count {
          // We've matched the entire search prefix, continue to all children
          newDepth = searchPrefix.count
        } else {
          // Mismatch before matching the full prefix - no matches in this subtree
          return
        }
      } else {
        // Full partial matched, advance by its length
        newDepth += partialLength
      }
    }

    if newDepth >= searchPrefix.count {
      // We've matched the entire search prefix, visit all children
      var index = inode.startIndex
      let end = inode.endIndex
      while index != end {
        if let child = inode.child(at: index) {
          _prefixVisit(child, searchPrefix, newDepth + 1, body)
        }
        index = inode.index(after: index)
      }
    } else if newDepth < searchPrefix.count {
      // Still need to match more of the prefix
      // Only proceed if we're still within bounds
      let nextByte = searchPrefix[newDepth]
      if let childIndex = inode.index(forKey: nextByte),
         let child = inode.child(at: childIndex) {
        _prefixVisit(child, searchPrefix, newDepth + 1, body)
      }
    }
  }
}