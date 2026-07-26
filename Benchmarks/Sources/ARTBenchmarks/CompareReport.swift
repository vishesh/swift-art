//===----------------------------------------------------------------------===//
//
// Head-to-head point-op comparison of RadixTree against every swift-collections
// map (and stdlib Dictionary) on the standard operations — build, lookup (hit and
// miss), full iteration, delete-all — for dense integer keys and shared-prefix
// string keys. Per-element nanoseconds, emitted as Markdown. Run with:
//
//   ARTBenchmarks compare [out.md]
//
//===----------------------------------------------------------------------===//

import ARTreeModule
import HashTreeCollections

#if UnstableSortedCollections
  import SortedCollections
#endif

// Per-element timings for one map type across the five point ops.
private struct Ops {
  var build = 0.0
  var hit = 0.0
  var miss = 0.0
  var iterate = 0.0
  var delete = 0.0
}

private func measure<M, K>(
  keys: [K], lookups: [K], misses: [K], iters: Int,
  empty: () -> M,
  insert: (inout M, K, Int) -> Void,
  lookup: (M, K) -> Int?,
  remove: (inout M, K) -> Void,
  iterate: (M) -> Void
) -> Ops {
  let n = keys.count
  var o = Ops()
  o.build = minPerElement(n, iterations: iters) {
    var m = empty()
    for (i, k) in keys.enumerated() { insert(&m, k, i) }
    blackHole(m)
  }

  var m = empty()
  for (i, k) in keys.enumerated() { insert(&m, k, i) }

  o.hit = minPerElement(n, iterations: iters) {
    var acc = 0
    for k in lookups { if let v = lookup(m, k) { acc &+= v } }
    blackHole(acc)
  }
  o.miss = minPerElement(n, iterations: iters) {
    var acc = 0
    for k in misses { if lookup(m, k) != nil { acc &+= 1 } }
    blackHole(acc)
  }
  o.iterate = minPerElement(n, iterations: iters) { iterate(m) }
  // Delete from a uniquely-owned map (built untimed), so no copy-on-write clone
  // is charged to delete — this measures delete-all, not snapshot-delete.
  o.delete = minPerElement(
    n, iterations: iters,
    setup: { () -> M in
      var d = empty()
      for (i, k) in keys.enumerated() { insert(&d, k, i) }
      return d
    },
    measured: { d in for k in lookups { remove(&d, k) } })
  blackHole(m)
  return o
}

private func row(_ name: String, _ o: Ops) -> String {
  String(
    format: "| %@ | %.0f | %.0f | %.0f | %.0f | %.0f |",
    name, o.build, o.hit, o.miss, o.iterate, o.delete)
}

public func runCompareReport(outputPath: String) {
  #if !UnstableSortedCollections
    print("compare requires the UnstableSortedCollections trait (SortedDictionary).")
  #else
    let n = 1_000_000
    let iters = 3
    let order = shuffledIndices(n)

    // --- Integer keys (dense, shuffled insertion order) ---
    let intKeys = order
    let intLookups = shuffledIndices(n)
    let intMisses = (0..<n).map { $0 + n }
    let rtInt = measure(
      keys: intKeys, lookups: intLookups, misses: intMisses, iters: iters,
      empty: { RadixTree<Int, Int>() }, insert: { $0[$1] = $2 }, lookup: { $0[$1] },
      remove: { $0[$1] = nil }, iterate: { for e in $0 { blackHole(e) } })
    let dictInt = measure(
      keys: intKeys, lookups: intLookups, misses: intMisses, iters: iters,
      empty: { [Int: Int]() }, insert: { $0[$1] = $2 }, lookup: { $0[$1] },
      remove: { $0[$1] = nil }, iterate: { for e in $0 { blackHole(e) } })
    let tdInt = measure(
      keys: intKeys, lookups: intLookups, misses: intMisses, iters: iters,
      empty: { TreeDictionary<Int, Int>() }, insert: { $0[$1] = $2 }, lookup: { $0[$1] },
      remove: { $0[$1] = nil }, iterate: { for e in $0 { blackHole(e) } })
    let sdInt = measure(
      keys: intKeys, lookups: intLookups, misses: intMisses, iters: iters,
      empty: { SortedDictionary<Int, Int>() }, insert: { $0[$1] = $2 }, lookup: { $0[$1] },
      remove: { $0[$1] = nil }, iterate: { for e in $0 { blackHole(e) } })
    print("done int")

    // --- Shared-prefix string keys ---
    let strKeys = makeSharedPrefixKeys(n)
    let strLookups = order.map { strKeys[$0] }
    let strMisses = (0..<n).map { makeSharedPrefixKeys(1, prefixLength: 48)[0] + "x\($0)" }
    let rtStr = measure(
      keys: strKeys, lookups: strLookups, misses: strMisses, iters: iters,
      empty: { RadixTree<String, Int>() }, insert: { $0[$1] = $2 }, lookup: { $0[$1] },
      remove: { $0[$1] = nil }, iterate: { for e in $0 { blackHole(e) } })
    let dictStr = measure(
      keys: strKeys, lookups: strLookups, misses: strMisses, iters: iters,
      empty: { [String: Int]() }, insert: { $0[$1] = $2 }, lookup: { $0[$1] },
      remove: { $0[$1] = nil }, iterate: { for e in $0 { blackHole(e) } })
    let tdStr = measure(
      keys: strKeys, lookups: strLookups, misses: strMisses, iters: iters,
      empty: { TreeDictionary<String, Int>() }, insert: { $0[$1] = $2 }, lookup: { $0[$1] },
      remove: { $0[$1] = nil }, iterate: { for e in $0 { blackHole(e) } })
    let sdStr = measure(
      keys: strKeys, lookups: strLookups, misses: strMisses, iters: iters,
      empty: { SortedDictionary<String, Int>() }, insert: { $0[$1] = $2 }, lookup: { $0[$1] },
      remove: { $0[$1] = nil }, iterate: { for e in $0 { blackHole(e) } })
    print("done string")

    let header =
      "| map | build | lookup hit | lookup miss | iterate | delete |\n|:--|--:|--:|--:|--:|--:|\n"
    var md = ""
    md += "# RadixTree vs swift-collections — point ops (per element)\n\n"
    md += "Per-element nanoseconds (lower is faster) at n = \(formatCount(n)), min of "
    md += "\(iters) runs, `-c release`, Apple Silicon. `Dictionary` (stdlib hash), "
    md += "`TreeDictionary` (CHAMP), `SortedDictionary` (B-tree). These are ART's "
    md += "*weakest* axes — the ordered-query strengths are in the `ordered` report.\n\n"

    md += "## Dense integer keys (shuffled)\n\n"
    md += header
    md += row("RadixTree", rtInt) + "\n"
    md += row("Dictionary", dictInt) + "\n"
    md += row("TreeDictionary", tdInt) + "\n"
    md += row("SortedDictionary", sdInt) + "\n\n"

    md += "## Shared-prefix string keys (~80-byte common prefix)\n\n"
    md += header
    md += row("RadixTree", rtStr) + "\n"
    md += row("Dictionary", dictStr) + "\n"
    md += row("TreeDictionary", tdStr) + "\n"
    md += row("SortedDictionary", sdStr) + "\n"

    do {
      try md.write(toFile: outputPath, atomically: true, encoding: .utf8)
      print("Wrote \(outputPath)")
    } catch {
      print("Failed to write \(outputPath): \(error)")
    }
  #endif
}
