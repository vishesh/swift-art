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
    // TODO
    fatalError("not implemented")
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
