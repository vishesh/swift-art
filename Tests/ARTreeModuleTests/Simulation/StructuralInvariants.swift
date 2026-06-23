import _CollectionsTestSupport
@testable import ARTreeModule

/// Walks the tree's internal structure and checks invariants against the model.
/// Returns `true` if every invariant held. Granular failures are recorded via the
/// `expect*` helpers; `ctx` is embedded in each message for reproducibility.
func checkInvariants<Value: Equatable>(
  _ tree: ARTree<Value>,
  _ model: ReferenceModel<Value>,
  _ ctx: @autoclosure () -> String
) -> Bool {
  typealias Spec = DefaultSpec<Value>
  var ok = true
  func fail(_ message: @autoclosure () -> String) {
    ok = false
    expectTrue(false, message())
  }

  guard let root = tree._root else {
    if !model.isEmpty { fail("tree is empty but model has \(model.count) entries: \(ctx())") }
    return ok
  }

  // A single-leaf root is valid: deletes can collapse a 1-key tree to a bare leaf.
  if root.type == .leaf {
    let leaf: NodeLeaf<Spec> = root.toLeafNode()
    if model.count != 1 {
      fail("single-leaf root but model has \(model.count) entries: \(ctx())")
    } else if model.get(leaf.key) != leaf.value {
      fail("single-leaf root disagrees with model for key \(leaf.key): \(ctx())")
    }
    return ok
  }

  var leaves: [[UInt8]] = []

  func walk(_ raw: RawNode) {
    if raw.type == .leaf {
      let leaf: NodeLeaf<Spec> = raw.toLeafNode()
      let key = leaf.key
      leaves.append(key)
      if model.get(key) != leaf.value {
        fail("leaf value disagrees with model for key \(key): \(ctx())")
      }
      return
    }

    let node: any InternalNode<Spec> = raw.toInternalNode()

    if node.partialLength > Const.maxPartialLength {
      fail("partialLength \(node.partialLength) exceeds max "
        + "\(Const.maxPartialLength) (\(raw.type)): \(ctx())")
    }

    let cap = capacityOf(raw.type)
    var seen = 0
    var idx = node.startIndex
    while idx != node.endIndex {
      if let child = node.child(at: idx) {
        seen += 1
        walk(child)
      } else {
        fail("nil child at a live index \(idx) (\(raw.type)): \(ctx())")
      }
      idx = node.index(after: idx)
    }

    // `count` must match the children actually present, and a non-empty node must
    // never exceed its capacity. Note: a `count == 1` internal node is legal — the
    // delete-merge path keeps one when the merged prefix would overflow
    // `maxPartialLength` — so we do NOT assert a lower bound of 2.
    if node.count != seen {
      fail("count field \(node.count) != actual children \(seen) (\(raw.type)): \(ctx())")
    }
    if node.count < 1 {
      fail("internal node has no children (\(raw.type)): \(ctx())")
    }
    if node.count > cap {
      fail("count \(node.count) exceeds capacity \(cap) (\(raw.type)): \(ctx())")
    }
  }

  walk(root)

  // In-order traversal must yield strictly increasing keys.
  if leaves.count >= 2 {
    for i in 1..<leaves.count where !leaves[i - 1].lexicographicallyPrecedes(leaves[i]) {
      fail("leaves not strictly increasing at \(i): \(leaves[i - 1]) !< \(leaves[i]): \(ctx())")
      break
    }
  }

  // The set of leaves must be exactly the model's keys.
  if leaves.count != model.count {
    fail("structural leaf count \(leaves.count) != model count \(model.count): \(ctx())")
  }

  return ok
}

private func capacityOf(_ type: NodeType) -> Int {
  switch type {
  case .leaf: return 0
  case .node4: return 4
  case .node16: return 16
  case .node48: return 48
  case .node256: return 256
  }
}
