struct Node16<Spec: ARTreeSpec> {
  var storage: Storage
}

extension Node16 {
  static var type: NodeType { .node16 }
  static var numKeys: Int { 16 }

  // Lane index per slot, used to mask out stale slots in the SIMD key search.
  static var _laneIndices: SIMD16<UInt8> {
    SIMD16<UInt8>(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15)
  }
}

extension Node16 {
  var keys: UnsafeMutableBufferPointer<KeyPart> {
    storage.withBodyPointer {
      UnsafeMutableBufferPointer(
        start: $0.assumingMemoryBound(to: KeyPart.self),
        count: Self.numKeys
      )
    }
  }

  var childs: UnsafeMutableBufferPointer<RawNode?> {
    storage.withBodyPointer {
      let childPtr = $0.advanced(by: Self.numKeys * MemoryLayout<KeyPart>.stride)
        .assumingMemoryBound(to: RawNode?.self)
      return UnsafeMutableBufferPointer(start: childPtr, count: Self.numKeys)
    }
  }
}

extension Node16 {
  static func allocate() -> NodeStorage<Self> {
    let storage = NodeStorage<Self>.allocate()

    storage.update { node in
      UnsafeMutableRawPointer(node.keys.baseAddress!)
        .bindMemory(to: UInt8.self, capacity: Self.numKeys)
      UnsafeMutableRawPointer(node.childs.baseAddress!)
        .bindMemory(to: RawNode?.self, capacity: Self.numKeys)
    }

    return storage
  }

  static func allocate(copyFrom: Node4<Spec>) -> NodeStorage<Self> {
    let storage = Self.allocate()

    storage.update { newNode in
      newNode.copyHeader(from: copyFrom)
      UnsafeMutableRawBufferPointer(newNode.keys).copyBytes(from: copyFrom.keys)
      // Move (don't retain) the children out of the discarded source.
      UnsafeMutableRawBufferPointer(newNode.childs).copyBytes(
        from: UnsafeMutableRawBufferPointer(copyFrom.childs))
      Self.forgetChildren(copyFrom.childs)
    }

    return storage
  }

  static func allocate(copyFrom: Node48<Spec>) -> NodeStorage<Self> {
    let storage = NodeStorage<Self>.allocate()

    storage.update { newNode in
      newNode.copyHeader(from: copyFrom)

      // Move (don't retain) the surviving children out of the discarded source.
      let src = copyFrom.childs.baseAddress!
      let dst = newNode.childs.baseAddress!
      var slot = 0
      for key: UInt8 in 0...255 {
        let childPosition = Int(copyFrom.keys[Int(key)])
        if childPosition == 0xFF {
          continue
        }

        newNode.keys[slot] = key
        Self.moveChild(from: src + childPosition, to: dst + slot)
        slot += 1
      }
      Self.forgetChildren(copyFrom.childs)

      assert(slot == newNode.count)
    }

    return storage
  }
}

extension Node16: InternalNode {
  static var size: Int {
    MemoryLayout<InternalNodeHeader>.stride + Self.numKeys
      * (MemoryLayout<KeyPart>.stride + MemoryLayout<RawNode?>.stride)
  }

  var startIndex: Index { 0 }
  var endIndex: Index { count }

  func index(forKey k: KeyPart) -> Index? {
    let count = self.count
    // SIMD compare of all 16 slots. Slots >= count are stale (removeChild leaves
    // them dirty), so mask them out or a stale byte == k is a false hit. At most
    // one valid lane matches, so sum its index out of an otherwise-zero vector.
    let keyVec = storage.withBodyPointer {
      $0.loadUnaligned(as: SIMD16<UInt8>.self)
    }
    let valid = Node16._laneIndices .< SIMD16<UInt8>(repeating: UInt8(count))
    let hit = (keyVec .== SIMD16<UInt8>(repeating: k)) .& valid
    if !any(hit) {
      return nil
    }
    let matchedLane = Node16._laneIndices.replacing(with: SIMD16<UInt8>(repeating: 0), where: .!hit)
    return Int(matchedLane.wrappedSum())
  }

  func index(after index: Index) -> Index {
    let next = index + 1
    if next >= count {
      return count
    } else {
      return next
    }
  }

  func _insertSlot(forKey k: KeyPart) -> Int? {
    // TODO: Binary search.
    if count >= Self.numKeys {
      return nil
    }

    for idx in 0..<count {
      if keys[idx] >= Int(k) {
        return idx
      }
    }

    return count
  }

  func child(at index: Index) -> RawNode? {
    assert(index < Self.numKeys, "maximum \(Self.numKeys) childs allowed, given index = \(index)")
    assert(index < count, "not enough childs in node")
    return childs[index]
  }

  func childOpaque(forKey k: KeyPart) -> UnsafeMutableRawPointer? {
    guard let index = index(forKey: k) else { return nil }
    return UnsafeRawPointer(childs.baseAddress! + index).loadUnaligned(
      as: UnsafeMutableRawPointer?.self)
  }

  func keyByte(at index: Index) -> KeyPart {
    return keys[index]
  }

  mutating func addChild(forKey k: KeyPart, node: RawNode) -> UpdateResult<RawNode?> {
    if let slot = _insertSlot(forKey: k) {
      // `slot == count` is an append; `keys[slot]` there is unused/stale (removeChild
      // doesn't clear it), so only check for a real duplicate when slot < count.
      assert(slot == count || keys[slot] != k, "node for key \(k) already exists")
      keys.shiftRight(startIndex: slot, endIndex: count - 1, by: 1)
      childs.shiftRight(startIndex: slot, endIndex: count - 1, by: 1)
      keys[slot] = k
      childs[slot] = node
      count += 1
      return .noop
    } else {
      return Node48.allocate(copyFrom: self).update { newNode in
        _ = newNode.addChild(forKey: k, node: node)
        return .replaceWith(newNode.rawNode)
      }
    }
  }

  mutating func removeChild(at index: Index) -> UpdateResult<RawNode?> {
    assert(index < Self.numKeys, "index can't >= 16 in Node16")
    assert(index < count, "not enough childs in node")

    keys[index] = 0
    childs[index] = nil

    count -= 1
    keys.shiftLeft(startIndex: index + 1, endIndex: count, by: 1)
    childs.shiftLeft(startIndex: index + 1, endIndex: count, by: 1)
    childs[count] = nil  // Clear the last item.

    if count == 3 {
      // Shrink to Node4.
      let newNode = Node4.allocate(copyFrom: self)
      return .replaceWith(newNode.node.rawNode)
    }

    return .noop
  }

  mutating func withChildRef<R>(at index: Index, _ body: (RawNode.SlotRef) -> R) -> R {
    assert(index < count, "not enough childs in node")
    let ref = childs.baseAddress! + index
    return body(ref)
  }
}

extension Node16: ARTNode {
  final class Buffer: RawNodeBuffer {
    deinit {
      var node = Node16(buffer: self)
      for idx in 0..<16 {
        node.childs[idx] = nil
      }
      node.count = 0
    }
  }

  func clone() -> NodeStorage<Self> {
    let storage = Self.allocate()

    storage.update { newNode in
      newNode.copyHeader(from: self)
      for idx in 0..<Self.numKeys {
        newNode.keys[idx] = self.keys[idx]
        newNode.childs[idx] = self.childs[idx]
      }
    }

    return storage
  }
}
