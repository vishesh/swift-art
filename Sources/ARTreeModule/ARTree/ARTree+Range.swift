// Ordered range scan. Because keys are stored as binary-comparable bytes, the
// trie's in-order traversal is key order, and a bounded scan prunes any subtree
// whose accumulated byte prefix already falls entirely below the lower bound or
// above the upper bound — visiting O(matches + boundary nodes) rather than O(n).

// Lexicographic byte compare: <0, 0, or >0.
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

// Every key in a subtree starts with `prefix`. True iff all of them are < lo.
@inline(__always)
private func _prefixEntirelyBelow(_ prefix: [UInt8], _ lo: UnsafeRawBufferPointer) -> Bool {
  let n = Swift.min(prefix.count, lo.count)
  var i = 0
  while i < n {
    if prefix[i] < lo[i] { return true }
    if prefix[i] > lo[i] { return false }
    i += 1
  }
  return false
}

// True iff every key in the subtree (all starting with `prefix`) is > hi.
@inline(__always)
private func _prefixEntirelyAbove(_ prefix: [UInt8], _ hi: UnsafeRawBufferPointer) -> Bool {
  let n = Swift.min(prefix.count, hi.count)
  var i = 0
  while i < n {
    if prefix[i] > hi[i] { return true }
    if prefix[i] < hi[i] { return false }
    i += 1
  }
  // Prefix matches hi over the shared length: only above hi if it extends past it
  // (e.g. prefix "abc" vs hi "ab" — every key here is > "ab").
  return prefix.count > hi.count
}

@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension ARTreeImpl {
  // Visit every (keyBytes, value) with lo <= key <= hi (inclusive), in ascending
  // key order. `keyBytes` is valid only for the duration of the call to `body`.
  func forEachInRange(
    lowerBytes lo: UnsafeRawBufferPointer,
    upperBytes hi: UnsafeRawBufferPointer,
    _ body: (UnsafeRawBufferPointer, Value) -> Void
  ) {
    guard let root = _root, _lexCompare(lo, hi) <= 0 else { return }
    var prefix: [UInt8] = []
    prefix.reserveCapacity(32)
    _rangeVisit(root, &prefix, lo, hi, body)
  }

  private func _rangeVisit(
    _ node: RawNode,
    _ prefix: inout [UInt8],
    _ lo: UnsafeRawBufferPointer,
    _ hi: UnsafeRawBufferPointer,
    _ body: (UnsafeRawBufferPointer, Value) -> Void
  ) {
    if node.type == .leaf {
      let leaf = NodeLeaf<Spec>(buffer: node.buf)
      leaf.withKeyValue { keyPtr, valuePtr in
        let key = UnsafeRawBufferPointer(keyPtr)
        if _lexCompare(lo, key) <= 0 && _lexCompare(key, hi) <= 0 {
          body(key, valuePtr.pointee)
        }
      }
      return
    }

    let inode: any InternalNode<Spec> = node.toInternalNode()
    let savedLength = prefix.count

    let partialLength = inode.partialLength
    if partialLength > 0 {
      let partial = inode.partialBytes
      for i in 0..<partialLength { prefix.append(partial[i]) }
    }

    if !_prefixEntirelyBelow(prefix, lo) && !_prefixEntirelyAbove(prefix, hi) {
      var index = inode.startIndex
      let end = inode.endIndex
      while index != end {
        if let child = inode.child(at: index) {
          prefix.append(inode.keyByte(at: index))
          if !_prefixEntirelyBelow(prefix, lo) && !_prefixEntirelyAbove(prefix, hi) {
            _rangeVisit(child, &prefix, lo, hi, body)
          }
          prefix.removeLast()
        }
        index = inode.index(after: index)
      }
    }

    prefix.removeLast(prefix.count - savedLength)
  }
}
