public typealias KeyPart = UInt8
public typealias Key = [KeyPart]

protocol ARTNode<Spec> {
  associatedtype Spec: ARTreeSpec
  associatedtype Buffer: RawNodeBuffer

  typealias Value = Spec.Value
  typealias Storage = UnmanagedNodeStorage<Self>

  static var type: NodeType { get }

  var storage: Storage { get }
  var type: NodeType { get }
  var rawNode: RawNode { get }

  func clone() -> NodeStorage<Self>

  init(storage: Storage)
}

extension ARTNode {
  init(buffer: RawNodeBuffer) {
    self.init(storage: Self.Storage(raw: buffer))
  }
}

extension ARTNode {
  var rawNode: RawNode { RawNode(buf: self.storage.ref.takeUnretainedValue()) }
  var type: NodeType { Self.type }
}

extension ARTNode {
  func equals(_ other: any ARTNode<Spec>) -> Bool {
    return self.rawNode == other.rawNode
  }
}
