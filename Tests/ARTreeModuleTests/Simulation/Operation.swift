// Recorded operations and simulation configuration.
//
// The op-log stores payloads as plain `Int`s and keys as `[UInt8]` — never the
// `LifetimeTracked` value instances. That keeps the log replayable and prevents it
// from holding references that would defeat the end-of-run leak check.

indirect enum Op: CustomStringConvertible {
  case insert(key: [UInt8], payload: Int)
  case delete(key: [UInt8])
  case lookup(key: [UInt8])
  case snapshot
  case dropSnapshot(Int)
  case forkMutate(Int, [Op])
  case restore(Int)

  var description: String {
    switch self {
    case .insert(let k, let p): return "insert(\(k), #\(p))"
    case .delete(let k): return "delete(\(k))"
    case .lookup(let k): return "lookup(\(k))"
    case .snapshot: return "snapshot"
    case .dropSnapshot(let i): return "dropSnapshot(\(i))"
    case .forkMutate(let i, let ops): return "forkMutate(snap=\(i), \(ops))"
    case .restore(let i): return "restore(\(i))"
    }
  }
}

enum OpKind { case insert, delete, lookup, snapshot, dropSnapshot, forkMutate, restore }

struct OpWeights {
  var insert = 50
  var delete = 25
  var lookup = 10
  var snapshot = 6
  var forkMutate = 6
  var restore = 3
  var dropSnapshot = 3
}

struct SimulationConfig {
  var keygenKind: KeygenKind
  var steps = 3000
  var checkInterval = 250
  var maxSnapshots = 8
  var forkOps: ClosedRange<Int> = 1...12
  /// P(an insert reuses an existing key -> exercises the replace path).
  var pExisting = 0.35
  /// P(a delete targets a key that is actually present).
  var pPresent = 0.7
  /// When false, snapshot/fork/restore are disabled so every mutation is
  /// single-owner — required for the `.checksUniquePath` suite.
  var cowEnabled = true
  /// Print each op to stderr (unbuffered) before applying it. For pinning down a
  /// library trap that aborts the process before the op-log can be dumped.
  var trace = false
  var weights = OpWeights()
}
