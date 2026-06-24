struct Node48<Spec: ARTreeSpec> {
  var storage: Storage
}

extension Node48 {
  static var type: NodeType { .node48 }
  static var numKeys: Int { 48 }
}

extension Node48 {
  var keys: UnsafeMutableBufferPointer<KeyPart> {
    storage.withBodyPointer {
      UnsafeMutableBufferPointer(
        start: $0.assumingMemoryBound(to: KeyPart.self),
        count: 256
      )
    }
  }

  var childs: UnsafeMutableBufferPointer<RawNode?> {
    storage.withBodyPointer {
      let childPtr = $0.advanced(by: 256 * MemoryLayout<KeyPart>.stride)
        .assumingMemoryBound(to: RawNode?.self)
      return UnsafeMutableBufferPointer(start: childPtr, count: Self.numKeys)
    }
  }
}

extension Node48 {
  static func allocate() -> NodeStorage<Self> {
    let storage = NodeStorage<Self>.allocate()

    storage.update { newNode in
      UnsafeMutableRawPointer(newNode.keys.baseAddress!)
        .bindMemory(to: UInt8.self, capacity: Self.numKeys)
      UnsafeMutableRawPointer(newNode.childs.baseAddress!)
        .bindMemory(to: RawNode?.self, capacity: Self.numKeys)

      for idx in 0..<256 {
        newNode.keys[idx] = 0xFF
      }
    }

    return storage
  }

  static func allocate(copyFrom: Node16<Spec>) -> NodeStorage<Self> {
    let storage = Self.allocate()

    storage.update { newNode in
      newNode.copyHeader(from: copyFrom)
      // Move (don't retain) the children out of the discarded source.
      UnsafeMutableRawBufferPointer(newNode.childs).copyBytes(
        from: UnsafeMutableRawBufferPointer(copyFrom.childs))
      for (idx, key) in copyFrom.keys.enumerated() {
        newNode.keys[Int(key)] = UInt8(idx)
      }

      Self.forgetChildren(copyFrom.childs)
    }

    return storage
  }

  static func allocate(copyFrom: Node256<Spec>) -> NodeStorage<Self> {
    let storage = Self.allocate()

    storage.update { newNode in
      newNode.copyHeader(from: copyFrom)
      // Move (don't retain) the children out of the discarded source; test
      // emptiness via the raw bits to avoid a retaining read.
      let src = copyFrom.childs.baseAddress!
      let dst = newNode.childs.baseAddress!
      var slot = 0
      for key in 0..<256 {
        let srcSlot = src + key
        if UnsafeRawPointer(srcSlot).loadUnaligned(as: UInt.self) == 0 {
          continue
        }

        newNode.keys[key] = UInt8(slot)
        Self.moveChild(from: srcSlot, to: dst + slot)
        slot += 1
      }
      Self.forgetChildren(copyFrom.childs)
    }

    return storage
  }
}

extension Node48: InternalNode {
  static var size: Int {
    MemoryLayout<InternalNodeHeader>.stride + 256 * MemoryLayout<KeyPart>.stride + Self.numKeys
      * MemoryLayout<RawNode?>.stride
  }

  var startIndex: Index {
    if count == 0 {
      return endIndex
    } else {
      return index(after: -1)
    }
  }

  var endIndex: Index { 256 }

  func index(forKey k: KeyPart) -> Index? {
    let childIndex = Int(keys[Int(k)])
    return childIndex == 0xFF ? nil : Int(k)
  }

  func index(after index: Index) -> Index {
    for idx: Int in index + 1..<256 {
      if keys[idx] != 0xFF {
        return idx
      }
    }

    return 256
  }

  func child(at index: Index) -> RawNode? {
    assert(index < 256, "invalid index")
    let slot = Int(keys[index])
    assert(slot != 0xFF, "no child at given slot")
    return childs[slot]
  }

  // Override the default child(forKey:) to index the slot table once, not twice.
  func child(forKey k: KeyPart) -> RawNode? {
    let slot = keys[Int(k)]
    return slot == 0xFF ? nil : childs[Int(slot)]
  }

  func childOpaque(forKey k: KeyPart) -> UnsafeMutableRawPointer? {
    let slot = keys[Int(k)]
    if slot == 0xFF { return nil }
    return UnsafeRawPointer(childs.baseAddress! + Int(slot)).loadUnaligned(as: UnsafeMutableRawPointer?.self)
  }

  mutating func addChild(forKey k: KeyPart, node: RawNode) -> UpdateResult<RawNode?> {
    if count < Self.numKeys {
      assert(keys[Int(k)] == 0xFF, "node for key \(k) already exists")

      guard let slot = findFreeSlot() else {
        fatalError("cannot find free slot in Node48")
      }

      keys[Int(k)] = KeyPart(slot)
      childs[slot] = node

      self.count += 1
      return .noop
    } else {
      return Node256.allocate(copyFrom: self).update { newNode in
        _ = newNode.addChild(forKey: k, node: node)
        return .replaceWith(newNode.rawNode)
      }
    }
  }

  public mutating func removeChild(at index: Index) -> UpdateResult<RawNode?> {
    assert(index < 256, "invalid index")
    let targetSlot = Int(keys[index])
    assert(targetSlot != 0xFF, "slot is empty already")

    // Don't compact the child array: readers use the key→slot map and addChild
    // reuses holes, so compacting would only cost an O(256) reverse-lookup here.
    childs[targetSlot] = nil
    keys[index] = 0xFF
    count -= 1

    // Shrink the node to Node16 if needed.
    if count == 13 {
      let newNode = Node16.allocate(copyFrom: self)
      return .replaceWith(newNode.node.rawNode)
    }

    return .noop
  }

  private func findFreeSlot() -> Int? {
    for (index, child) in childs.enumerated() {
      if child == nil {
        return index
      }
    }

    return nil
  }

  mutating func withChildRef<R>(at index: Index, _ body: (RawNode.SlotRef) -> R) -> R {
    assert(index < 256, "invalid index")
    assert(keys[index] != 0xFF, "child doesn't exist in given slot")
    let ref = childs.baseAddress! + Int(keys[index])
    return body(ref)
  }
}

extension Node48: ARTNode {
  final class Buffer: RawNodeBuffer {
    deinit {
      var node = Node48(buffer: self)
      for idx in 0..<48 {
        node.childs[idx] = nil
      }
      node.count = 0
    }
  }

  func clone() -> NodeStorage<Self> {
    let storage = Self.allocate()

    storage.update { newNode in
      newNode.copyHeader(from: self)
      for idx in 0..<256 {
        let slot = keys[idx]
        newNode.keys[idx] = slot
        if slot != 0xFF {
          newNode.childs[Int(slot)] = childs[Int(slot)]
        }
      }
    }

    return storage
  }
}
