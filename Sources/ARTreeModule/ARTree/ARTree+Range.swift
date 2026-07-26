// Ordered range and seek scans. Keys are stored as binary-comparable bytes, so
// the trie's in-order (ascending key-byte) child traversal is key order.
//
// The scan tracks, during descent, whether the path is still flush against the
// lower bound (`loActive`) and/or the upper bound (`hiActive`). Once a subtree is
// strictly interior to the range — both flags off — it is emitted wholesale with
// no per-node comparisons. Only the two boundary "edges" of the range do byte
// work, and there only against the single relevant bound byte. This replaces the
// earlier scheme that rebuilt the accumulated prefix in a heap `[UInt8]` and
// re-ran an O(prefix) lexicographic compare at every node.

// Lexicographic byte compare: <0, 0, or >0. Used only on the (few) boundary leaves.
@inline(__always)
private func _lexCompare(_ a: UnsafeRawBufferPointer, _ b: UnsafeRawBufferPointer) -> Int {
  let n = Swift.min(a.count, b.count)
  var i = 0
  while i < n {
    if a[i] != b[i] { return a[i] < b[i] ? -1 : 1 }
    i += 1
  }
  if a.count == b.count { return 0 }
  return a.count < b.count ? -1 : 1
}

@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension ARTreeImpl {
  // Visit every (keyBytes, value) with lo <= key <= hi (inclusive), ascending.
  // `keyBytes` is valid only for the duration of the `body` call.
  func forEachInRange(
    lowerBytes lo: UnsafeRawBufferPointer,
    upperBytes hi: UnsafeRawBufferPointer,
    _ body: (UnsafeRawBufferPointer, Value) -> Void
  ) {
    guard let root = _root, _lexCompare(lo, hi) <= 0 else { return }
    withExtendedLifetime(root.buf) {
      _ = _rangeVisit(root, depth: 0, loActive: true, hiActive: true, lo, hi) {
        body($0, $1)
        return true
      }
    }
  }

  // Visit every (keyBytes, value) with key >= lo, ascending — an unbounded-above
  // range. `body` returns false to stop early. The descent to the first match is
  // O(key length), independent of tree size: this is the seek a radix tree does
  // cheaply and a comparison tree pays O(log n) prefix-rescanning compares for.
  @discardableResult
  func forEachFrom(
    lowerBytes lo: UnsafeRawBufferPointer,
    _ body: (UnsafeRawBufferPointer, Value) -> Bool
  ) -> Bool {
    guard let root = _root else { return true }
    return withExtendedLifetime(root.buf) {
      _rangeVisit(root, depth: 0, loActive: true, hiActive: false, lo, nil, body)
    }
  }

  // Emit an entire subtree in ascending key order, no bound checks. Returns false
  // if `body` asked to stop. Shared with the prefix scan.
  func _emitSubtree(
    _ node: RawNode, _ body: (UnsafeRawBufferPointer, Value) -> Bool
  ) -> Bool {
    if node.type == .leaf {
      let leaf = NodeLeaf<Spec>(buffer: node.buf)
      return leaf.withKeyValue { keyPtr, valuePtr in
        body(UnsafeRawBufferPointer(keyPtr), valuePtr.pointee)
      }
    }
    let inode: any InternalNode<Spec> = node.toInternalNode()
    var index = inode.startIndex
    let end = inode.endIndex
    while index != end {
      if let child = inode.child(at: index), !_emitSubtree(child, body) {
        return false
      }
      index = inode.index(after: index)
    }
    return true
  }

  // `hi == nil` means unbounded above (`hiActive` is then always false).
  private func _rangeVisit(
    _ node: RawNode, depth: Int,
    loActive: Bool, hiActive: Bool,
    _ lo: UnsafeRawBufferPointer, _ hi: UnsafeRawBufferPointer?,
    _ body: (UnsafeRawBufferPointer, Value) -> Bool
  ) -> Bool {
    // Strictly interior to the range: nothing below can violate either bound.
    if !loActive && !hiActive { return _emitSubtree(node, body) }

    if node.type == .leaf {
      let leaf = NodeLeaf<Spec>(buffer: node.buf)
      return leaf.withKeyValue { keyPtr, valuePtr in
        let key = UnsafeRawBufferPointer(keyPtr)
        if loActive && _lexCompare(key, lo) < 0 { return true }
        if hiActive, let hi, _lexCompare(key, hi) > 0 { return true }
        return body(key, valuePtr.pointee)
      }
    }

    let inode: any InternalNode<Spec> = node.toInternalNode()
    var depth = depth
    var loActive = loActive
    var hiActive = hiActive

    // Walk the compressed partial prefix, one path byte at a time, folding each
    // into the active flags (or pruning the whole subtree if a bound is crossed).
    let partialLength = inode.partialLength
    if partialLength > 0 {
      let partial = inode.partialBytes
      for i in 0..<partialLength {
        let pb = partial[i]
        if loActive {
          if depth >= lo.count {
            loActive = false
          }  // path longer than lo ⇒ > lo
          else if pb < lo[depth] {
            return true
          }  // whole subtree < lo
          else if pb > lo[depth] {
            loActive = false
          }
        }
        if hiActive, let hi {
          if depth >= hi.count {
            return true
          }  // path longer than hi ⇒ > hi
          else if pb > hi[depth] {
            return true
          }  // whole subtree > hi
          else if pb < hi[depth] {
            hiActive = false
          }
        }
        depth += 1
        if !loActive && !hiActive { return _emitSubtree(node, body) }
      }
    }

    var index = inode.startIndex
    let end = inode.endIndex
    while index != end {
      let cb = inode.keyByte(at: index)

      var childLo = loActive
      if loActive {
        if depth >= lo.count {
          childLo = false  // lo exhausted ⇒ every child byte extends past lo
        } else if cb < lo[depth] {
          index = inode.index(after: index)
          continue  // this child's subtree is entirely < lo
        } else if cb > lo[depth] {
          childLo = false
        }
      }

      var childHi = hiActive
      if hiActive, let hi {
        if depth >= hi.count {
          break  // hi exhausted ⇒ this and all higher children are > hi
        } else if cb > hi[depth] {
          break  // children are ascending, so all remaining are > hi
        } else if cb < hi[depth] {
          childHi = false
        }
      }

      if let child = inode.child(at: index) {
        if !_rangeVisit(
          child, depth: depth + 1, loActive: childLo, hiActive: childHi, lo, hi, body)
        {
          return false
        }
      }
      index = inode.index(after: index)
    }
    return true
  }
}
