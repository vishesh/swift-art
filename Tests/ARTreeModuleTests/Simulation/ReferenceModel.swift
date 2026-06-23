// A trivially-correct reference model for the ART engine.
//
// The engine maps raw `[UInt8]` keys to values and iterates in lexicographic byte
// order, so a plain dictionary plus a sort is an obviously-correct oracle. The
// model also keeps an explicit key list so the simulator can sample existing keys
// deterministically — `Dictionary` iteration order is randomized per process and
// would otherwise break seed-based reproducibility.
struct ReferenceModel<Value> {
  private var dict: [[UInt8]: Value] = [:]
  private var keyList: [[UInt8]] = []
  private var keyPos: [[UInt8]: Int] = [:]

  var count: Int { dict.count }
  var isEmpty: Bool { dict.isEmpty }

  /// Live keys in a deterministic (insertion/swap) order, suitable for sampling.
  var keys: [[UInt8]] { keyList }

  func get(_ key: [UInt8]) -> Value? { dict[key] }
  func contains(_ key: [UInt8]) -> Bool { dict[key] != nil }

  /// Mirrors `ARTreeImpl.insert`: returns `true` if the key was newly inserted.
  @discardableResult
  mutating func insert(_ key: [UInt8], _ value: Value) -> Bool {
    let isNew = dict[key] == nil
    dict[key] = value
    if isNew {
      keyPos[key] = keyList.count
      keyList.append(key)
    }
    return isNew
  }

  mutating func remove(_ key: [UInt8]) {
    guard dict[key] != nil else { return }
    dict[key] = nil
    let pos = keyPos[key]!
    let last = keyList.count - 1
    if pos != last {
      let moved = keyList[last]
      keyList[pos] = moved
      keyPos[moved] = pos
    }
    keyList.removeLast()
    keyPos[key] = nil
  }

  /// Entries in the order the tree iterates them (lexicographic over key bytes).
  func sortedEntries() -> [(key: [UInt8], value: Value)] {
    dict.sorted { $0.key.lexicographicallyPrecedes($1.key) }
  }
}
