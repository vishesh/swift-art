//===----------------------------------------------------------------------===//
//
// The workload a radix tree is actually for: ordered queries — a bounded range
// scan and a successor ("first key >= x") seek. These are where RadixTree beats
// the maps people reach for:
//
//   * vs Dictionary / TreeDictionary (hash maps): no contest — a hash map has no
//     order, so an ordered query degrades to a full O(n) scan. RadixTree answers
//     in O(seek + matches), so its lead grows without bound as n grows.
//   * vs SortedDictionary (B-tree): the honest peer. RadixTree's seek is O(key
//     length), flat in n; the B-tree's is O(log n) prefix-rescanning compares.
//     The B-tree still wins the *scan* (contiguous leaves vs scattered nodes), so
//     this is shown plainly rather than cherry-picked.
//
//   ARTBenchmarks ordered [out.md]
//
//===----------------------------------------------------------------------===//

import ARTreeModule
import HashTreeCollections

#if UnstableSortedCollections
  import SortedCollections
#endif

private func winCell(radix: Double, other: Double) -> String {
  radix <= other
    ? String(format: "**%.1f× faster**", other / radix)
    : String(format: "%.1f× slower", radix / other)
}

public func runOrderedQueryReport(outputPath: String) {
  #if !UnstableSortedCollections
    print("ordered requires the UnstableSortedCollections trait (SortedDictionary).")
  #else
    let sizes = [1_000, 10_000, 100_000, 1_000_000]
    let window = 16
    let iters = 3
    let qFast = 2_000  // ordered maps answer cheaply, so time many queries
    let qScan = 20  // the hash maps scan all n per query, so time few

    var rangeRows: [String] = []
    var seekRows: [String] = []

    for n in sizes {
      let keys = makeSharedPrefixKeys(n)  // ascending, ~80-byte shared prefix
      var rt = RadixTree<String, Int>()
      var dict = [String: Int]()
      var tdict = TreeDictionary<String, Int>()
      var sd = SortedDictionary<String, Int>()
      for i in 0..<n {
        rt[keys[i]] = i
        dict[keys[i]] = i
        tdict[keys[i]] = i
        sd[keys[i]] = i
      }

      var rng = SplitMix64(state: 0x51ED_270B_2E76_9C1D)
      let fast = (0..<qFast).map { _ in Int(rng.next() % UInt64(n - window)) }
      let scan = (0..<qScan).map { _ in Int(rng.next() % UInt64(n - window)) }

      // --- Range window [keys[s], keys[s+window-1]] ---
      let rtRange = minPerElement(qFast, iterations: iters) {
        var acc = 0
        for s in fast {
          rt.forEachEntry(from: keys[s], to: keys[s + window - 1]) { _, v in acc &+= v }
        }
        blackHole(acc)
      }
      let sdRange = minPerElement(qFast, iterations: iters) {
        var acc = 0
        for s in fast {
          let hi = keys[s + window - 1]
          var idx = sd.index(forKey: keys[s])!
          while idx != sd.endIndex, sd[idx].key <= hi {
            acc &+= sd[idx].value
            sd.formIndex(after: &idx)
          }
        }
        blackHole(acc)
      }
      let dictRange = minPerElement(qScan, iterations: iters) {
        var acc = 0
        for s in scan {
          let lo = keys[s]
          let hi = keys[s + window - 1]
          for (k, v) in dict where k >= lo && k <= hi { acc &+= v }
        }
        blackHole(acc)
      }
      let tdictRange = minPerElement(qScan, iterations: iters) {
        var acc = 0
        for s in scan {
          let lo = keys[s]
          let hi = keys[s + window - 1]
          for (k, v) in tdict where k >= lo && k <= hi { acc &+= v }
        }
        blackHole(acc)
      }
      rangeRows.append(
        String(
          format: "| %@ | %.0f | %.0f | %.0f | %.0f | %@ |", formatCount(n),
          rtRange, sdRange, dictRange, tdictRange, winCell(radix: rtRange, other: sdRange)))

      // --- Successor seek: first key >= target ---
      let rtSeek = minPerElement(qFast, iterations: iters) {
        var acc = 0
        for s in fast { acc &+= rt.firstEntry(from: keys[s])?.value ?? -1 }
        blackHole(acc)
      }
      let dictSeek = minPerElement(qScan, iterations: iters) {
        var acc = 0
        for s in scan {  // min key >= target requires visiting every entry
          let target = keys[s]
          var bestKey: String?
          var bestVal = -1
          for (k, v) in dict where k >= target {
            if bestKey == nil || k < bestKey! {
              bestKey = k
              bestVal = v
            }
          }
          acc &+= bestVal
        }
        blackHole(acc)
      }
      seekRows.append(
        String(
          format: "| %@ | %.0f | %.0f | %@ |", formatCount(n),
          rtSeek, dictSeek, winCell(radix: rtSeek, other: dictSeek)))

      blackHole(rt)
      blackHole(sd)
      blackHole(dict)
      blackHole(tdict)
      print("done n=\(n)")
    }

    var md = ""
    md += "# Ordered queries — RadixTree vs swift-collections\n\n"
    md += "Shared-prefix `(String, Int)` keys (~80-byte common prefix). Times are "
    md += "**per query** in nanoseconds (lower is faster). Apple Silicon, `-c release`, "
    md += "min of \(iters) runs.\n\n"
    md += "The fair peer is **`SortedDictionary`** (B-tree) — the only other *ordered* "
    md += "map here — so the ratio column compares against it. `Dictionary` and "
    md += "`TreeDictionary` are hash maps: they have no order, so an ordered query has "
    md += "to scan **all n** entries; their columns show why you reach for an ordered "
    md += "map at all, not that RadixTree is 'fast'.\n\n"

    md += "## Range scan — sum a \(window)-key window\n\n"
    md +=
      "| n | RadixTree | SortedDictionary | Dictionary | TreeDictionary | RadixTree vs SortedDict |\n"
    md += "|--:|--:|--:|--:|--:|:--|\n"
    md += rangeRows.joined(separator: "\n") + "\n\n"
    md += "Against the B-tree RadixTree **loses** the scan (~1.7–2×): its seek to the "
    md += "window is flat in n, but the B-tree walks contiguous leaves while RadixTree "
    md += "walks scattered per-key leaves. RadixTree only pulls ahead of the *hash* "
    md += "maps, once n is large enough that their O(n) scan dominates.\n\n"

    md += "## Successor seek — first key ≥ x\n\n"
    md += "`SortedDictionary` exposes no public successor/ceiling method, so it can't be "
    md += "benchmarked here through its own API (a B-tree could do this in O(log n) "
    md += "internally); the fair RadixTree-vs-B-tree \"locate a key\" comparison is the "
    md += "exact point lookup in the `shared-prefix` report (RadixTree ~2.3× slower at "
    md += "1M, closing with n). Against a hash map the seek is a full O(n) scan:\n\n"
    md += "| n | RadixTree | Dictionary | RadixTree vs Dictionary |\n"
    md += "|--:|--:|--:|:--|\n"
    md += seekRows.joined(separator: "\n") + "\n\n"
    md += "`firstEntry(from:)` descends in O(key length), independent of n.\n"

    do {
      try md.write(toFile: outputPath, atomically: true, encoding: .utf8)
      print("Wrote \(outputPath)")
    } catch {
      print("Failed to write \(outputPath): \(error)")
    }
  #endif
}
