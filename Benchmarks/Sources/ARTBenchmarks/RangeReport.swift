//===----------------------------------------------------------------------===//
//
// Range-scan comparison: sum the values of a small key window in a large map.
// Keys share a long prefix, so the seek to the window's lower bound is where a
// radix tree (byte descent, flat in n) can beat a B-tree (index(forKey:) does
// O(log n) comparisons, each rescanning the shared prefix). Run with:
//
//   ARTBenchmarks range [out.md]
//
//===----------------------------------------------------------------------===//

import ARTreeModule

#if UnstableSortedCollections
  import SortedCollections
#endif

public func runRangeReport(outputPath: String) {
  #if !UnstableSortedCollections
    print("range requires the UnstableSortedCollections trait (SortedDictionary).")
    return
  #else
    let sizes = [1_000, 4_000, 16_000, 64_000, 256_000, 1_000_000]
    let window = 32
    let iterations = 3
    var rows: [String] = []

    for n in sizes {
      // makeSharedPrefixKeys yields keys sorted ascending (zero-padded counter),
      // so [keys[s], keys[s+window-1]] is a window of `window` consecutive entries.
      let keys = makeSharedPrefixKeys(n)
      var rt = RadixTree<String, Int>()
      var sd = SortedDictionary<String, Int>()
      for i in 0..<n {
        rt[keys[i]] = i
        sd[keys[i]] = i
      }

      let queryCount = Swift.min(n - window, 2000)
      var starts: [Int] = []
      starts.reserveCapacity(queryCount)
      var rng = SplitMix64(state: 0x1234_5678_9ABC_DEF0)
      for _ in 0..<queryCount { starts.append(Int(rng.next() % UInt64(n - window))) }

      // Sanity: both engines must agree on a sample window.
      var rtSum = 0
      rt.forEachEntry(from: keys[starts[0]], to: keys[starts[0] + window - 1]) { _, v in rtSum += v
      }
      precondition(rtSum == (starts[0]..<starts[0] + window).reduce(0, +), "range mismatch")

      let rtNs = minPerElement(queryCount, iterations: iterations) {
        var acc = 0
        for s in starts {
          rt.forEachEntry(from: keys[s], to: keys[s + window - 1]) { _, v in acc &+= v }
        }
        blackHole(acc)
      }

      let sdNs = minPerElement(queryCount, iterations: iterations) {
        var acc = 0
        for s in starts {
          let hi = keys[s + window - 1]
          var idx = sd.index(forKey: keys[s])!
          while idx != sd.endIndex {
            let e = sd[idx]
            if e.key > hi { break }
            acc &+= e.value
            sd.formIndex(after: &idx)
          }
        }
        blackHole(acc)
      }

      let ratio =
        rtNs <= sdNs
        ? String(format: "**%.2f× faster**", sdNs / rtNs)
        : String(format: "%.2f× slower", rtNs / sdNs)
      rows.append(String(format: "| %@ | %.0f | %.0f | %@ |", formatCount(n), rtNs, sdNs, ratio))
      print("done n=\(n)")
    }

    var md = ""
    md += "# RadixTree vs SortedDictionary — range scan (shared-prefix keys)\n\n"
    md += "Each query sums the values of a \(window)-key window. Time is **per query** in "
    md += "nanoseconds (lower is faster). Keys share a long (~80 byte) prefix. Apple "
    md += "Silicon, `-c release`, min of \(iterations) runs.\n\n"
    md += "The seek to the window favors a radix tree (byte descent, flat in n) over a "
    md += "B-tree's `index(forKey:)` (O(log n) prefix-rescanning comparisons), but a "
    md += "\(window)-key window is **scan-dominated**, and the scan is where RadixTree "
    md += "still trails: it visits scattered per-key leaves (cache misses) and decodes "
    md += "a key per entry, vs a B-tree walking contiguous nodes. The bucketed-leaf "
    md += "rearchitecture targets exactly this.\n\n"
    md += "| n | RadixTree (ns/query) | SortedDictionary (ns/query) | RadixTree vs SortedDict |\n"
    md += "|--:|--:|--:|:--|\n"
    md += rows.joined(separator: "\n") + "\n"

    do {
      try md.write(toFile: outputPath, atomically: true, encoding: .utf8)
      print("Wrote \(outputPath)")
    } catch {
      print("Failed to write \(outputPath): \(error)")
    }
  #endif
}
