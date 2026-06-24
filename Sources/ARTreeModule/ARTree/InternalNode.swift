protocol InternalNode<Spec>: ARTNode {
  typealias Value = Spec.Value
  typealias Index = Int
  typealias Header = InternalNodeHeader
  typealias Children = UnsafeMutableBufferPointer<RawNode?>

  static var size: Int { get }

  var partialLength: Int { get }
  var partialBytes: PartialBytes { get set }

  var count: Int { get set }
  var startIndex: Index { get }
  var endIndex: Index { get }

  func index(forKey: KeyPart) -> Index?
  func index(after: Index) -> Index

  func child(forKey: KeyPart) -> RawNode?  // TODO: Remove
  func child(at: Index) -> RawNode?  // TODO: Remove

  mutating func addChild(forKey: KeyPart, node: RawNode) -> UpdateResult<RawNode?>
  mutating func addChild(forKey: KeyPart, node: some ARTNode<Spec>) -> UpdateResult<RawNode?>

  mutating func removeChild(at: Index) -> UpdateResult<RawNode?>

  mutating func withChildRef<R>(at: Index, _ body: (RawNode.SlotRef) -> R) -> R
}

struct NodeReference {
  var _ptr: RawNode.SlotRef

  init(_ ptr: RawNode.SlotRef) {
    self._ptr = ptr
  }
}

extension NodeReference {
  var pointee: RawNode? {
    @inline(__always) get { _ptr.pointee }
    @inline(__always) set { _ptr.pointee = newValue }
  }
}

extension InternalNode {
  var partialLength: Int {
    get {
      storage.withHeaderPointer {
        Int($0.pointee.partialLength)
      }
    }
    set {
      assert(newValue <= Const.maxPartialLength)
      storage.withHeaderPointer {
        $0.pointee.partialLength = KeyPart(newValue)
      }
    }
  }

  var partialBytes: PartialBytes {
    get {
      storage.withHeaderPointer {
        $0.pointee.partialBytes
      }
    }
    set {
      storage.withHeaderPointer {
        $0.pointee.partialBytes = newValue
      }
    }
  }

  var count: Int {
    get {
      storage.withHeaderPointer {
        Int($0.pointee.count)
      }
    }
    set {
      storage.withHeaderPointer {
        $0.pointee.count = UInt16(newValue)
      }
    }
  }

  func child(forKey k: KeyPart) -> RawNode? {
    return index(forKey: k).flatMap { child(at: $0) }
  }

  mutating func addChild(forKey k: KeyPart, node: some ARTNode<Spec>) -> UpdateResult<RawNode?> {
    return addChild(forKey: k, node: node.rawNode)
  }

  mutating func copyHeader(from: any InternalNode) {
    self.storage.withHeaderPointer { header in
      header.pointee.count = UInt16(from.count)
      header.pointee.partialLength = UInt8(from.partialLength)
      header.pointee.partialBytes = from.partialBytes
    }
  }

  // Calculates the index at which prefix mismatches.
  func prefixMismatch(withKey key: Key, fromIndex depth: Int) -> Int {
    key.withUnsafeBytes { prefixMismatch(withKey: $0, fromIndex: depth) }
  }

  func prefixMismatch(withKey key: UnsafeRawBufferPointer, fromIndex depth: Int) -> Int {
    // Read the header once and compare prefix bytes directly. Going through the
    // `partialBytes` property here would copy the whole 8-byte FixedArray (and
    // re-enter the storage closure) on every compared byte.
    return storage.withHeaderPointer { header in
      let partialLength = Int(header.pointee.partialLength)
      assert(partialLength <= Const.maxPartialLength, "partial length is always bounded")
      let maxComp = min(partialLength, key.count - depth)

      return withUnsafeBytes(of: &header.pointee.partialBytes) { partial in
        for index in 0..<maxComp {
          if partial[index] != key[depth + index] {
            return index
          }
        }
        return maxComp
      }
    }
  }

  // TODO: Look everywhere its used, and try to avoid unnecessary RC traffic.
  static func retainChildren(_ children: Children, count: Int) {
    for idx in 0..<count {
      if let c = children[idx] {
        _ = Unmanaged.passRetained(c.buf)
      }
    }
  }
}

@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension InternalNode {
  mutating func maybeReadChild<R>(
    forKey k: KeyPart,
    ref: inout NodeReference,
    _ body: (any ARTNode<Spec>, Bool) -> R
  ) -> R? {
    if count == 0 {
      return nil
    }

    return index(forKey: k).flatMap { index in
      self.withChildRef(at: index) { ptr in
        ref = NodeReference(ptr)
        return body(ptr.pointee!.toARTNode(), ptr.pointee!.isUnique)
      }
    }
  }
}

enum UpdateResult<T> {
  case noop
  case replaceWith(T)
}

@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension InternalNode {
  @inline(__always)
  fileprivate mutating func withSelfOrClone<R>(
    isUnique: Bool,
    _ body: (any InternalNode<Spec>) -> R
  ) -> R {
    if isUnique {
      return body(self)
    }

    let clone = clone()
    let node: any InternalNode<Spec> = clone.node
    return body(node)
  }

  mutating func updateChild(
    forKey k: KeyPart,
    isUniquePath: Bool,
    body: (inout RawNode?, Bool) -> UpdateResult<RawNode?>
  )
    -> UpdateResult<RawNode?>
  {

    guard let childPosition = index(forKey: k) else {
      return .noop
    }

    let isUnique = isUniquePath && withChildRef(at: childPosition) { $0.pointee!.isUnique }
    var child = child(at: childPosition)
    let action = body(&child, isUnique)

    // TODO: This is ugly. Rewrite.
    switch action {
    case .noop:
      // No action asked to be executed from body.
      return .noop

    case .replaceWith(nil) where self.count == 1:
      // Body asked to remove the last child. So just delete ourselves too.
      return .replaceWith(nil)

    case .replaceWith(nil):
      // Body asked to remove the child. Removing the child can lead to these situations:
      // - Remove successful. No more action need.
      // - Remove successful, but that left us with one child, and we can apply
      //   path compression right now.
      // - Remove successful, but we can shrink ourselves now with newValue.
      return withSelfOrClone(isUnique: isUnique) {
        var selfRef = $0
        switch selfRef.removeChild(at: childPosition) {
        case .noop:
          // Child removed successfully, nothing to do. Keep ourselves.
          return .replaceWith(selfRef.rawNode)

        case .replaceWith(let newValue?):
          if newValue.type != .leaf && selfRef.count == 1 {
            assert(selfRef.type == .node4, "only node4 can have count = 1")
            let slf: Node4<Spec> = selfRef as! Node4<Spec>

            // Merge slf into its single child:
            //   merged prefix = slf.prefix + connectingByte + child.prefix
            let slfLength = slf.partialLength
            let childLength = newValue.toInternalNode(of: Spec.self).partialLength
            let mergedLength = slfLength + 1 + childLength

            if mergedLength <= Const.maxPartialLength {
              // Path compression rewrites the surviving child's prefix in place. That
              // child is a *sibling* of the deleted node, not on the unique mutation
              // path, so `isUnique` (which tracks the path) says nothing about it — it
              // can still be shared with other trees (copies). Always clone it before
              // mutating, so we never corrupt a shared sibling.
              let childRaw = newValue.clone(spec: Spec.self)
              var node: any InternalNode<Spec> = childRaw.toInternalNode()

              let slfBytes = slf.partialBytes
              let childBytes = node.partialBytes
              var merged = PartialBytes(repeating: 0)
              for i in 0..<slfLength {
                merged[i] = slfBytes[i]
              }
              merged[slfLength] = slf.keys[0]
              for i in 0..<childLength {
                merged[slfLength + 1 + i] = childBytes[i]
              }
              node.partialBytes = merged
              node.partialLength = mergedLength
              return .replaceWith(childRaw)
            }

            // Merged prefix exceeds maxPartialLength; keep slf as a single-child node.
            return .replaceWith(selfRef.rawNode)
          }
          return .replaceWith(newValue)

        case .replaceWith(nil):
          fatalError("unexpected state: removeChild should not be called with count == 1")
        }
      }

    case .replaceWith(let newValue?):
      // Body asked to replace the child, with a new one. Wont affect
      // the self count.
      return withSelfOrClone(isUnique: isUnique) {
        var selfRef = $0
        selfRef.withChildRef(at: childPosition) {
          $0.pointee = newValue
        }
        return .replaceWith(selfRef.rawNode)
      }
    }
  }
}
