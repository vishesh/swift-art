@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension ARTreeImpl {
  public func getValue(key: Key) -> Value? {
    key.withUnsafeBytes { getValue(keyBytes: $0) }
  }

  public func getValue(keyBytes key: UnsafeRawBufferPointer) -> Value? {
    guard let rootRaw = _root else { return nil }

    // The root (held by `_root`) keeps the whole reachable subtree alive for this
    // read, so we walk it with unretained opaque pointers — no retain/release per
    // hop. `withExtendedLifetime` keeps the root pinned past the final deref.
    return withExtendedLifetime(rootRaw.buf) { () -> Value? in
      var current = Unmanaged.passUnretained(rootRaw.buf).toOpaque()
      var depth = 0
      while depth <= key.count {
        let node = Unmanaged<RawNodeBuffer>.fromOpaque(current)
        let type = node._withUnsafeGuaranteedRef { $0.header }

        if type == .leaf {
          return node._withUnsafeGuaranteedRef { buf in
            let leaf = NodeLeaf<Spec>(buffer: buf)
            return leaf.keyEquals(with: key) ? leaf.value : nil
          }
        }

        // nil means the key is absent (prefix mismatch or no matching child).
        let next: UnsafeMutableRawPointer? = node._withUnsafeGuaranteedRef { buf in
          switch type {
          case .node4: return _descend(Node4<Spec>(buffer: buf), key, &depth)
          case .node16: return _descend(Node16<Spec>(buffer: buf), key, &depth)
          case .node48: return _descend(Node48<Spec>(buffer: buf), key, &depth)
          case .node256: return _descend(Node256<Spec>(buffer: buf), key, &depth)
          case .leaf: return nil  // handled above
          }
        }

        guard let next else { return nil }
        current = next
      }

      return nil
    }
  }

  // One step down an internal node: returns the child buffer to visit next as an
  // unretained opaque pointer, or nil if the key is absent (prefix mismatch or no
  // matching child).
  @inline(__always)
  private func _descend<N: InternalNode<Spec>>(
    _ node: N, _ key: UnsafeRawBufferPointer, _ depth: inout Int
  ) -> UnsafeMutableRawPointer? {
    let partialLength = node.partialLength
    if partialLength > 0 {
      let prefixLen = node.prefixMismatch(withKey: key, fromIndex: depth)
      assert(prefixLen <= Const.maxPartialLength, "partial length is always bounded")
      if prefixLen != partialLength {
        return nil
      }
      depth += partialLength
    }

    let child = node.childOpaque(forKey: key[depth])
    depth += 1
    return child
  }

  public mutating func getRange(start: Key, end: Key) {
    // TODO
    fatalError("not implemented")
  }
}
