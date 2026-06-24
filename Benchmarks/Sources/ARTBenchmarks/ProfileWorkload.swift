//===----------------------------------------------------------------------===//
//
// A fixed RadixTree workload that runs one operation in a loop for a fixed
// duration, giving a profiler (Instruments / samply / sample) a stable hot path
// to sample. Run with:
//
//   ARTBenchmarks profile <build|lookup|iterate|delete> [n] [seconds]
//
// See scripts/profile.sh for capturing CPU / allocation traces.
//
//===----------------------------------------------------------------------===//

import ARTreeModule
import Foundation

public func runProfile(op: String, n: Int, seconds: Double) {
  let keys = makeSharedPrefixKeys(n)
  let order = shuffledIndices(n)
  let budgetNs = UInt64(seconds * 1_000_000_000)
  let start = DispatchTime.now().uptimeNanoseconds
  func running() -> Bool { (DispatchTime.now().uptimeNanoseconds &- start) < budgetNs }
  var rounds = 0

  switch op {
  case "build":
    while running() {
      var m = RadixTree<String, Int>()
      for i in 0..<n { m[keys[i]] = i }
      blackHole(m)
      rounds += 1
    }

  case "lookup":
    var m = RadixTree<String, Int>()
    for i in 0..<n { m[keys[i]] = i }
    var acc = 0
    while running() {
      for idx in order { acc &+= m[keys[idx]] ?? 0 }
      rounds += 1
    }
    blackHole(acc)
    blackHole(m)

  case "iterate":
    var m = RadixTree<String, Int>()
    for i in 0..<n { m[keys[i]] = i }
    var acc = 0
    while running() {
      for (_, v) in m { acc &+= v }
      rounds += 1
    }
    blackHole(acc)
    blackHole(m)

  case "delete":
    // Rebuild then delete-all each round (delete needs a populated map); both
    // show up in the trace as distinct call trees.
    while running() {
      var m = RadixTree<String, Int>()
      for i in 0..<n { m[keys[i]] = i }
      for idx in order { m[keys[idx]] = nil }
      blackHole(m)
      rounds += 1
    }

  default:
    print("unknown op '\(op)'. Use build | lookup | iterate | delete.")
    return
  }

  print("profile \(op): n=\(n), ran \(rounds) round(s) in ~\(seconds)s")
}
