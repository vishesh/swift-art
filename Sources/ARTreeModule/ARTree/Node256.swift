struct Node256<Spec: ARTreeSpec> {
  var storage: Storage
}

extension Node256 {
  static var type: NodeType { .node256 }
  static var numKeys: Int { 256 }
}

extension Node256 {
  var childs: UnsafeMutableBufferPointer<RawNode?> {
    storage.withBodyPointer {
      UnsafeMutableBufferPointer(
        start: $0.assumingMemoryBound(to: RawNode?.self),
        count: 256)
    }
  }
}

extension Node256 {
  static func allocate() -> NodeStorage<Self> {
    let storage = NodeStorage<Self>.allocate()

    _ = storage.update { newNode in
      UnsafeMutableRawPointer(newNode.childs.baseAddress!)
        .bindMemory(to: RawNode?.self, capacity: Self.numKeys)
    }

    return storage
  }

  static func allocate(copyFrom: Node48<Spec>) -> NodeStorage<Self> {
    let storage = Self.allocate()

    storage.update { newNode in
      newNode.copyHeader(from: copyFrom)
      // Move (don't retain) the children out of the discarded source.
      let src = copyFrom.childs.baseAddress!
      let dst = newNode.childs.baseAddress!
      for key in 0..<256 {
        let slot = Int(copyFrom.keys[key])
        if slot < 0xFF {
          Self.moveChild(from: src + slot, to: dst + key)
        }
      }
      Self.forgetChildren(copyFrom.childs)

      assert(newNode.count == 48, "should have exactly 48 childs")
    }

    return storage
  }
}

extension Node256: InternalNode {
  static var size: Int {
    MemoryLayout<InternalNodeHeader>.stride + 256 * MemoryLayout<RawNode?>.stride
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
    return childs[Int(k)] != nil ? Int(k) : nil
  }

  func index(after idx: Index) -> Index {
    for idx in idx + 1..<256 {
      if childs[idx] != nil {
        return idx
      }
    }

    return 256
  }

  func child(at index: Index) -> RawNode? {
    assert(index < 256, "maximum 256 childs allowed")
    return childs[index]
  }

  func child(forKey k: KeyPart) -> RawNode? {
    return childs[Int(k)]
  }

  func childOpaque(forKey k: KeyPart) -> UnsafeMutableRawPointer? {
    return UnsafeRawPointer(childs.baseAddress! + Int(k)).loadUnaligned(
      as: UnsafeMutableRawPointer?.self)
  }

  // In Node256 the index IS the key byte (0...255).
  func keyByte(at index: Index) -> KeyPart {
    return KeyPart(index)
  }

  mutating func addChild(forKey k: KeyPart, node: RawNode) -> UpdateResult<RawNode?> {
    assert(childs[Int(k)] == nil, "node for key \(k) already exists")
    childs[Int(k)] = node
    count += 1
    return .noop
  }

  mutating func removeChild(at index: Index) -> UpdateResult<RawNode?> {
    assert(index < 256, "invalid index")
    childs[index] = nil
    count -= 1

    if count == 40 {
      let newNode = Node48.allocate(copyFrom: self)
      return .replaceWith(newNode.node.rawNode)
    }

    return .noop
  }

  mutating func withChildRef<R>(at index: Index, _ body: (RawNode.SlotRef) -> R) -> R {
    assert(index < 256, "invalid index")
    let ref = childs.baseAddress! + index
    return body(ref)
  }
}

extension Node256: ARTNode {
  final class Buffer: RawNodeBuffer {
    deinit {
      var node = Node256(buffer: self)
      for idx in 0..<256 {
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
        newNode.childs[idx] = childs[idx]
      }
    }

    return storage
  }
}
