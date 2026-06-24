//===----------------------------------------------------------------------===//
//
// A focused, self-timed comparison of RadixTree against SortedDictionary on the
// radix tree's advertised sweet spot — long, shared-prefix keys — swept across
// sizes. Writes a Markdown report. Run with:
//
//   ARTBenchmarks shared-prefix [out.md]
//
//===----------------------------------------------------------------------===//

import Foundation
import ARTreeModule
#if UnstableSortedCollections
import SortedCollections
#endif

@inline(never)
private func blackHole<T>(_ x: T) {}

// Deterministic RNG so the lookup order is reproducible across runs.
private struct SplitMix64 {
  var state: UInt64
  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}

private func shuffledIndices(_ n: Int) -> [Int] {
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
// comparison-based map (every `<` rescans the prefix) and the radix tree's
// intended sweet spot.
private func makeKeys(_ n: Int, prefixLength: Int) -> [String] {
  let prefix = "/org/example/service/v1/resource/" + String(repeating: "a", count: prefixLength) + "/"
  return (0..<n).map { prefix + String(format: "%012d", $0) }
}

// Returns the minimum per-element time in nanoseconds over `iterations` runs.
private func minPerElement(_ n: Int, iterations: Int, _ body: () -> Void) -> Double {
  var best = Double.infinity
  for _ in 0..<iterations {
    let t0 = DispatchTime.now().uptimeNanoseconds
    body()
    let t1 = DispatchTime.now().uptimeNanoseconds
    best = Swift.min(best, Double(t1 &- t0))
  }
  return best / Double(n)
}

private func ratioCell(radix: Double, sorted: Double) -> String {
  // How RadixTree compares to SortedDictionary.
  if radix <= sorted {
    return String(format: "**%.2f× faster**", sorted / radix)
  } else {
    return String(format: "%.2f× slower", radix / sorted)
  }
}

public func runSharedPrefixReport(outputPath: String) {
  #if !UnstableSortedCollections
  print("shine-report requires the UnstableSortedCollections trait (SortedDictionary).")
  return
  #else
  let sizes = [1_000, 4_000, 16_000, 64_000, 256_000, 1_000_000, 4_000_000]
  let prefixLength = 48
  let iterations = 3

  var buildRows: [String] = []
  var lookupRows: [String] = []

  for n in sizes {
    let keys = makeKeys(n, prefixLength: prefixLength)
    let order = shuffledIndices(n)

    let rtBuild = minPerElement(n, iterations: iterations) {
      var m = RadixTree<String, Int>()
      for i in 0..<n { m[keys[i]] = i }
      blackHole(m)
    }
    let sdBuild = minPerElement(n, iterations: iterations) {
      var m = SortedDictionary<String, Int>()
      for i in 0..<n { m[keys[i]] = i }
      blackHole(m)
    }
    buildRows.append(
      String(format: "| %@ | %.0f | %.0f | %@ |", formatN(n), rtBuild, sdBuild,
             ratioCell(radix: rtBuild, sorted: sdBuild)))

    var rt = RadixTree<String, Int>()
    for i in 0..<n { rt[keys[i]] = i }
    var sd = SortedDictionary<String, Int>()
    for i in 0..<n { sd[keys[i]] = i }

    let rtLook = minPerElement(n, iterations: iterations) {
      var acc = 0
      for idx in order { acc &+= rt[keys[idx]] ?? -1 }
      blackHole(acc)
    }
    let sdLook = minPerElement(n, iterations: iterations) {
      var acc = 0
      for idx in order { acc &+= sd[keys[idx]] ?? -1 }
      blackHole(acc)
    }
    lookupRows.append(
      String(format: "| %@ | %.0f | %.0f | %@ |", formatN(n), rtLook, sdLook,
             ratioCell(radix: rtLook, sorted: sdLook)))

    blackHole(rt)
    blackHole(sd)
    print("done n=\(n)")
  }

  var md = ""
  md += "# RadixTree vs SortedDictionary — shared-prefix keys\n\n"
  md += "Keys are a long, deeply-namespaced shared prefix (~80 bytes) followed by a "
  md += "zero-padded counter, so they differ only near the end. This is the radix "
  md += "tree's intended sweet spot and the worst case for a comparison-based "
  md += "B-tree, whose every key comparison must rescan the shared prefix.\n\n"
  md += "Times are **per-element** in nanoseconds (lower is faster); the last column "
  md += "compares `RadixTree` to `SortedDictionary` from swift-collections. "
  md += "Apple Silicon, `-c release`, min of \(iterations) runs.\n\n"

  md += "## Lookup (successful)\n\n"
  md += "| n | RadixTree (ns) | SortedDictionary (ns) | RadixTree vs SortedDict |\n"
  md += "|--:|--:|--:|:--|\n"
  md += lookupRows.joined(separator: "\n") + "\n\n"

  md += "## Build (insert n keys)\n\n"
  md += "| n | RadixTree (ns) | SortedDictionary (ns) | RadixTree vs SortedDict |\n"
  md += "|--:|--:|--:|:--|\n"
  md += buildRows.joined(separator: "\n") + "\n"

  do {
    try md.write(toFile: outputPath, atomically: true, encoding: .utf8)
    print("Wrote \(outputPath)")
  } catch {
    print("Failed to write \(outputPath): \(error)")
  }
  #endif
}

private func formatN(_ n: Int) -> String {
  if n >= 1_000_000 { return "\(n / 1_000_000)M" }
  if n >= 1_000 { return "\(n / 1_000)k" }
  return "\(n)"
}
