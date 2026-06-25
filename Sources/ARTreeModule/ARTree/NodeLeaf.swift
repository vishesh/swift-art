struct NodeLeaf<Spec: ARTreeSpec> {
  typealias Value = Spec.Value
  var storage: Storage
}

extension NodeLeaf {
  static var type: NodeType { .leaf }
}

extension NodeLeaf {
  static func allocate(key: Key, value: Value) -> NodeStorage<Self> {
    key.withUnsafeBytes { allocate(keyBytes: $0, value: value) }
  }

  static func allocate(keyBytes key: UnsafeRawBufferPointer, value: Value) -> NodeStorage<Self> {
    let size = MemoryLayout<UInt32>.stride + key.count + MemoryLayout<Value>.stride
    let storage = NodeStorage<NodeLeaf>.create(type: .leaf, size: size)

    storage.update { leaf in
      leaf.keyLength = key.count
      leaf.withKeyValue { keyPtr, valuePtr in
        UnsafeMutableRawBufferPointer(keyPtr).copyBytes(from: key)
        valuePtr.pointee = value
      }
    }

    return storage
  }
}

extension NodeLeaf {
  typealias KeyPtr = UnsafeMutableBufferPointer<KeyPart>

  func withKeyBytes<R>(body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
    return try storage.withUnsafePointer {
      let keyStart = $0.advanced(by: MemoryLayout<UInt32>.stride)
      return try body(UnsafeRawBufferPointer(start: keyStart, count: Int(keyLength)))
    }
  }

  func withKey<R>(body: (KeyPtr) throws -> R) rethrows -> R {
    return try storage.withUnsafePointer {
      let keyPtr = UnsafeMutableBufferPointer(
        start:
          $0
          .advanced(by: MemoryLayout<UInt32>.stride)
          .assumingMemoryBound(to: KeyPart.self),
        count: Int(keyLength))
      return try body(keyPtr)
    }
  }

  func withValue<R>(body: (UnsafeMutablePointer<Value>) throws -> R) rethrows -> R {
    return try storage.withUnsafePointer {
      return try body(
        $0.advanced(by: MemoryLayout<UInt32>.stride)
          .advanced(by: keyLength)
          .assumingMemoryBound(to: Value.self))
    }
  }

  func withKeyValue<R>(body: (KeyPtr, UnsafeMutablePointer<Value>) throws -> R) rethrows -> R {
    return try storage.withUnsafePointer {
      let base = $0.advanced(by: MemoryLayout<UInt32>.stride)
      let keyPtr = UnsafeMutableBufferPointer(
        start: base.assumingMemoryBound(to: KeyPart.self),
        count: Int(keyLength)
      )
      let valuePtr = UnsafeMutableRawPointer(
        keyPtr.baseAddress?.advanced(by: Int(keyLength)))!
        .assumingMemoryBound(to: Value.self)
      return try body(keyPtr, valuePtr)
    }
  }

  var key: Key {
    withKeyBytes { Array($0) }
  }

  var keyLength: Int {
    get {
      storage.withUnsafePointer {
        Int($0.assumingMemoryBound(to: UInt32.self).pointee)
      }
    }
    set {
      storage.withUnsafePointer {
        $0.assumingMemoryBound(to: UInt32.self).pointee = UInt32(newValue)
      }
    }
  }

  var value: Value {
    withValue { $0.pointee }
  }
}

extension NodeLeaf {
  func keyEquals(with key: Key, depth: Int = 0) -> Bool {
    key.withUnsafeBytes { keyEquals(with: $0, depth: depth) }
  }

  func keyEquals(with key: UnsafeRawBufferPointer, depth: Int = 0) -> Bool {
    if key.count != keyLength {
      return false
    }

    return withKeyBytes { storedKey in
      for ii in depth..<key.count {
        if key[ii] != storedKey[ii] {
          return false
        }
      }
      return true
    }
  }

  func longestCommonPrefix(with other: Self, fromIndex: Int) -> Int {
    let maxComp = Int(min(keyLength, other.keyLength) - fromIndex)

    return withKey { keyPtr in
      return other.withKey { otherKeyPtr in
        for index in 0..<maxComp {
          if keyPtr[fromIndex + index] != otherKeyPtr[fromIndex + index] {
            return index
          }
        }
        return maxComp
      }
    }
  }
}

extension NodeLeaf: ARTNode {
  final class Buffer: RawNodeBuffer {
    deinit {
      _ = NodeLeaf(buffer: self).withValue {
        $0.deinitialize(count: 1)
      }
    }
  }

  func clone() -> NodeStorage<Self> {
    return withKeyBytes { Self.allocate(keyBytes: $0, value: value) }
  }
}
