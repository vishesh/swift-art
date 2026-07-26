@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension ARTreeImpl {
  public mutating func delete(key: Key) {
    key.withUnsafeBytes { delete(keyBytes: $0) }
  }

  public mutating func delete(keyBytes key: UnsafeRawBufferPointer) {
    if _root == nil {
      return
    }

    let isUnique = _root!.isUnique
    var child = _root
    switch _delete(child: &child, keyBytes: key, depth: 0, isUniquePath: isUnique) {
    case .noop:
      return
    case .replaceWith(let newValue):
      _root = newValue
    }
  }

  public mutating func deleteRange(start: Key, end: Key) {
    // Collect raw key bytes to delete
    var keysToDelete: [[UInt8]] = []
    start.withUnsafeBytes { startBytes in
      end.withUnsafeBytes { endBytes in
        forEachInRange(lowerBytes: startBytes, upperBytes: endBytes) { keyBytes, _ in
          keysToDelete.append(Array(keyBytes))
        }
      }
    }

    // Delete collected keys
    for keyBytes in keysToDelete {
      keyBytes.withUnsafeBytes { buffer in
        delete(keyBytes: buffer)
      }
    }
  }

  private mutating func _delete(
    child: inout RawNode?,
    keyBytes key: UnsafeRawBufferPointer,
    depth: Int,
    isUniquePath: Bool
  ) -> UpdateResult<RawNode?> {
    if child?.type == .leaf {
      let leaf: NodeLeaf<Spec> = child!.toLeafNode()
      if !leaf.keyEquals(with: key, depth: depth) {
        return .noop
      }

      return .replaceWith(nil)
    }

    if child?.type == .bucketLeaf {
      // Handle bucket leaf deletion
      var bucket = NodeBucketLeaf<Spec>(buffer: child!.buf)
      guard let index = bucket.findIndex(for: key, depth: depth) else {
        return .noop  // Key not found
      }

      // If this is the only entry, remove the whole bucket
      if bucket.count == 1 {
        return .replaceWith(nil)
      }

      // Clone if not unique
      if !isUniquePath {
        let clone = bucket.clone()
        child = clone.rawNode
        bucket = clone.node
      }

      // Remove the entry
      bucket.removeEntry(at: index)
      return .noop  // Bucket still exists with remaining entries
    }

    assert(!Const.testCheckUnique || isUniquePath, "unique path is expected in this test")
    var node: any InternalNode<Spec> = child!.toInternalNode()
    var newDepth = depth

    let partialLength = node.partialLength
    if partialLength > 0 {
      let matchedBytes = node.prefixMismatch(withKey: key, fromIndex: depth)
      assert(matchedBytes <= partialLength)
      if matchedBytes < partialLength {
        // Key diverges from this node's prefix, so it isn't present.
        return .noop
      }
      newDepth += matchedBytes
    }

    return node.updateChild(forKey: key[newDepth], isUniquePath: isUniquePath) {
      var child = $0
      return _delete(child: &child, keyBytes: key, depth: newDepth + 1, isUniquePath: $1)
    }
  }
}
