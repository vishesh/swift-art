import _CollectionsTestSupport
@testable import ARTreeModule

#if canImport(Foundation)
import Foundation
#endif

/// Runs one deterministic simulation. Everything derives from `seed`, so a failing
/// run reproduces by re-running with the same `(seed, config)`; the op-log is dumped
/// on the first failure for stepping through.
///
/// The whole run executes inside `withLifetimeTracking`, so after the tree, all
/// snapshots and the models are released, the tracker asserts no `LifetimeTracked`
/// value leaked (and `LifetimeTracked.deinit` traps on any double-release).
func runSimulation(
  seed: UInt64,
  config: SimulationConfig,
  file: StaticString = #file,
  line: UInt = #line
) {
  withLifetimeTracking(file: file, line: line) { tracker in
    let sim = ARTSimulator(seed: seed, config: config, tracker: tracker)
    sim.run()
  }
}

final class ARTSimulator {
  typealias V = LifetimeTracked<Int>

  let seed: UInt64
  let config: SimulationConfig
  let tracker: LifetimeTracker
  let keygen: KeyGenerator
  var rng: SplitMix64

  var tree = ARTree<V>()
  var model = ReferenceModel<V>()
  var snapshots: [(tree: ARTree<V>, model: ReferenceModel<V>, label: Int)] = []
  var opLog: [Op] = []
  var nextPayload = 0
  var nextLabel = 0
  var step = 0
  var failed = false

  init(seed: UInt64, config: SimulationConfig, tracker: LifetimeTracker) {
    self.seed = seed
    self.config = config
    self.tracker = tracker
    var r = SplitMix64(seed: seed)
    self.keygen = makeKeyGenerator(config.keygenKind, using: &r)
    self.rng = r
  }

  func run() {
    for s in 0..<config.steps {
      step = s
      applyRandomOp()
      if failed { break }
      if (s + 1) % config.checkInterval == 0 {
        runChecks()
        if failed { break }
      }
    }
    if !failed {
      step = config.steps
      runChecks()
    }
  }

  // MARK: - RNG helpers

  private func randomIndex(_ count: Int) -> Int { Int(rng.next() % UInt64(count)) }
  private func chance(_ p: Double) -> Bool { Double.random(in: 0..<1, using: &rng) < p }

  private func chooseKey(preferExisting p: Double) -> [UInt8] {
    if !model.isEmpty && chance(p) {
      return model.keys[randomIndex(model.count)]
    }
    return keygen.makeKey(using: &rng)
  }

  private func newValue() -> (value: V, payload: Int) {
    let p = nextPayload
    nextPayload += 1
    return (tracker.instance(for: p), p)
  }

  // MARK: - Op selection

  private func applyRandomOp() {
    switch pickKind() {
    case .insert: doInsert()
    case .delete: doDelete()
    case .lookup: doLookup()
    case .snapshot: doSnapshot()
    case .dropSnapshot: doDropSnapshot()
    case .forkMutate: doForkMutate()
    case .restore: doRestore()
    }
  }

  private func pickKind() -> OpKind {
    let w = config.weights
    var choices: [(OpKind, Int)] = [
      (.insert, w.insert), (.delete, w.delete), (.lookup, w.lookup),
    ]
    if config.cowEnabled {
      choices.append((.snapshot, w.snapshot))
      if !snapshots.isEmpty {
        choices.append((.forkMutate, w.forkMutate))
        choices.append((.restore, w.restore))
        choices.append((.dropSnapshot, w.dropSnapshot))
      }
    }
    let total = choices.reduce(0) { $0 + $1.1 }
    var r = Int(rng.next() % UInt64(total))
    for (kind, weight) in choices {
      if r < weight { return kind }
      r -= weight
    }
    return .insert
  }

  // MARK: - Ops on the working tree

  private func doInsert() {
    let key = chooseKey(preferExisting: config.pExisting)
    let (value, payload) = newValue()
    let op = Op.insert(key: key, payload: payload)
    trace(op)
    // NOTE: `ARTreeImpl.insert`'s Bool return is currently always `true` — it does
    // not signal new-vs-replace — so we don't assert on it. Insert correctness is
    // covered by the consistency, lookup and structural checks instead.
    tree.insert(key: key, value: value)
    model.insert(key, value)
    opLog.append(op)
  }

  private func doDelete() {
    let key = chooseKey(preferExisting: config.pPresent)
    let op = Op.delete(key: key)
    trace(op)
    tree.delete(key: key)
    model.remove(key)
    opLog.append(op)
  }

  private func doLookup() {
    let key = (!model.isEmpty && chance(0.5))
      ? model.keys[randomIndex(model.count)]
      : keygen.makeKey(using: &rng)
    let op = Op.lookup(key: key)
    trace(op)
    opLog.append(op)
    let got = tree.getValue(key: key)
    if got != model.get(key) {
      fail("getValue(\(key)) = \(stringify(got)), expected \(stringify(model.get(key)))")
    }
  }

  // MARK: - Ops on snapshots (copy-on-write)

  private func doSnapshot() {
    if snapshots.count >= config.maxSnapshots {
      snapshots.remove(at: randomIndex(snapshots.count))
    }
    snapshots.append((tree: tree, model: model, label: nextLabel))
    opLog.append(.snapshot)
    nextLabel += 1
  }

  private func doDropSnapshot() {
    guard !snapshots.isEmpty else { return }
    let i = randomIndex(snapshots.count)
    opLog.append(.dropSnapshot(i))
    snapshots.remove(at: i)
  }

  private func doRestore() {
    guard !snapshots.isEmpty else { return }
    let i = randomIndex(snapshots.count)
    tree = snapshots[i].tree
    model = snapshots[i].model
    opLog.append(.restore(i))
  }

  /// Mutate a live snapshot independently. Its own model tracks the changes; the
  /// working tree and every other snapshot must stay untouched — verified at the
  /// next checkpoint. This is the core copy-on-write divergence test.
  private func doForkMutate() {
    guard !snapshots.isEmpty else { return }
    let i = randomIndex(snapshots.count)
    let k = Int.random(in: config.forkOps, using: &rng)
    var sub: [Op] = []
    for _ in 0..<k {
      if !snapshots[i].model.isEmpty && chance(0.5) {
        let key = snapshots[i].model.keys[randomIndex(snapshots[i].model.count)]
        snapshots[i].tree.delete(key: key)
        snapshots[i].model.remove(key)
        sub.append(.delete(key: key))
      } else {
        let key: [UInt8]
        if !snapshots[i].model.isEmpty && chance(config.pExisting) {
          key = snapshots[i].model.keys[randomIndex(snapshots[i].model.count)]
        } else {
          key = keygen.makeKey(using: &rng)
        }
        let (value, payload) = newValue()
        snapshots[i].tree.insert(key: key, value: value)
        snapshots[i].model.insert(key, value)
        sub.append(.insert(key: key, payload: payload))
      }
    }
    opLog.append(.forkMutate(i, sub))
  }

  // MARK: - Checks

  private func runChecks() {
    let c = "seed=\(seed) step=\(step)"
    let working = consistencyCheck(tree, model, "working \(c)")
    let workingInv = checkInvariants(tree, model, "working \(c)")
    var allOK = working && workingInv
    for (i, snap) in snapshots.enumerated() {
      let tag = "snapshot#\(snap.label)[\(i)] \(c)"
      let sc = consistencyCheck(snap.tree, snap.model, tag)
      let si = checkInvariants(snap.tree, snap.model, tag)
      allOK = allOK && sc && si
    }
    if !allOK { dumpOnce() }
  }

  private func trace(_ op: Op) {
    guard config.trace else { return }
    #if canImport(Foundation)
    FileHandle.standardError.write(Data("[\(step)] \(op)\n".utf8))
    #endif
  }

  private func fail(_ message: @autoclosure () -> String) {
    dumpOnce()
    expectTrue(false, "seed=\(seed) step=\(step): \(message())")
  }

  /// Print a full, replayable repro once, on the first detected failure.
  private func dumpOnce() {
    if failed { return }
    failed = true
    var out = "\n=== ART simulation failure: seed=\(seed) step=\(step), kind=\(config.keygenKind) ===\n"
    out += "--- working tree ---\n\(tree.description)\n"
    out += "--- model (\(model.count) entries, sorted) ---\n"
    for e in model.sortedEntries() { out += "  \(e.key) -> #\(e.value.payload)\n" }
    out += "--- live snapshots: \(snapshots.count) ---\n"
    out += "--- op log (\(opLog.count) ops) ---\n"
    for (idx, op) in opLog.enumerated() { out += "  [\(idx)] \(op)\n" }
    out += "=== end dump ===\n"
    print(out)
  }
}

/// Consistency of a tree against its model: full ordered iteration and per-key
/// lookups. Returns `true` if everything matched.
func consistencyCheck<Value: Equatable>(
  _ tree: ARTree<Value>,
  _ model: ReferenceModel<Value>,
  _ ctx: @autoclosure () -> String
) -> Bool {
  var ok = true
  let actual = Array(tree)               // [([UInt8], Value)]
  let expected = model.sortedEntries()   // [(key: [UInt8], value: Value)]

  if actual.count != expected.count {
    expectEqual(actual.count, expected.count, "entry count: \(ctx())")
    ok = false
  }
  let n = min(actual.count, expected.count)
  var i = 0
  while i < n {
    if actual[i].0 != expected[i].key {
      expectEqual(actual[i].0, expected[i].key, "iteration key @\(i): \(ctx())")
      ok = false
      break
    }
    if actual[i].1 != expected[i].value {
      expectEqual(actual[i].1, expected[i].value, "iteration value @\(i): \(ctx())")
      ok = false
      break
    }
    i += 1
  }
  for key in model.keys {
    let got = tree.getValue(key: key)
    if got != model.get(key) {
      expectEqual(got, model.get(key), "getValue(\(key)): \(ctx())")
      ok = false
      break
    }
  }
  return ok
}

private func stringify<T>(_ value: T?) -> String { value.map { "\($0)" } ?? "nil" }
