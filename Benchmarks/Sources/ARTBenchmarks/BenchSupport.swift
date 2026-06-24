//===----------------------------------------------------------------------===//
//
// Shared helpers for the custom (non-CollectionsBenchmark) report and profiling
// modes: key generation, timing, deterministic shuffling, and a process-memory
// probe.
//
//===----------------------------------------------------------------------===//

import Darwin
import Foundation

@inline(never)
func blackHole<T>(_ x: T) {}

// Deterministic RNG so lookup order is reproducible across runs.
struct SplitMix64 {
  var state: UInt64
  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}

func shuffledIndices(_ n: Int) -> [Int] {
  var a = Array(0..<n)
  var rng = SplitMix64(state: 0xDEAD_BEEF_CAFE_F00D)
  var i = n - 1
  while i > 0 {
    let j = Int(rng.next() % UInt64(i + 1))
    a.swapAt(i, j)
    i -= 1
  }
  return a
}

// Long, deeply-namespaced shared prefix + a zero-padded counter, so most keys
// share a long prefix and differ only near the end — the worst case for a
// comparison-based map and the radix tree's intended sweet spot.
func makeSharedPrefixKeys(_ n: Int, prefixLength: Int = 48) -> [String] {
  let prefix =
    "/org/example/service/v1/resource/" + String(repeating: "a", count: prefixLength) + "/"
  return (0..<n).map { prefix + String(format: "%012d", $0) }
}

// Minimum per-element time in nanoseconds over `iterations` runs.
func minPerElement(_ n: Int, iterations: Int, _ body: () -> Void) -> Double {
  var best = Double.infinity
  for _ in 0..<iterations {
    let t0 = DispatchTime.now().uptimeNanoseconds
    body()
    let t1 = DispatchTime.now().uptimeNanoseconds
    best = Swift.min(best, Double(t1 &- t0))
  }
  return best / Double(n)
}

// Current physical memory footprint of this process, in bytes (the number
// Activity Monitor shows). Used as a before/after probe to attribute memory to a
// data structure.
func physFootprint() -> UInt64 {
  var info = task_vm_info_data_t()
  var count = mach_msg_type_number_t(
    MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
  let kr = withUnsafeMutablePointer(to: &info) {
    $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
      task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
    }
  }
  return kr == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0
}

func formatCount(_ n: Int) -> String {
  if n >= 1_000_000 { return "\(n / 1_000_000)M" }
  if n >= 1_000 { return "\(n / 1_000)k" }
  return "\(n)"
}
