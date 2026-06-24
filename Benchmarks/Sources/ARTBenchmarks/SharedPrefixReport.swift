//===----------------------------------------------------------------------===//
//
// A focused, self-timed comparison of RadixTree against SortedDictionary on the
// radix tree's advertised sweet spot — long, shared-prefix keys — swept across
// sizes. Writes a Markdown report. Run with:
//
//   ARTBenchmarks shared-prefix [out.md]
//
//===----------------------------------------------------------------------===//

import ARTreeModule

#if UnstableSortedCollections
  import SortedCollections
#endif

private func ratioCell(radix: Double, sorted: Double) -> String {
  if radix <= sorted {
    return String(format: "**%.2f× faster**", sorted / radix)
  } else {
    return String(format: "%.2f× slower", radix / sorted)
  }
}

public func runSharedPrefixReport(outputPath: String) {
  #if !UnstableSortedCollections
    print("shared-prefix requires the UnstableSortedCollections trait (SortedDictionary).")
    return
  #else
    let sizes = [1_000, 4_000, 16_000, 64_000, 256_000, 1_000_000, 4_000_000]
    let iterations = 3

    var buildRows: [String] = []
    var lookupRows: [String] = []

    for n in sizes {
      let keys = makeSharedPrefixKeys(n)
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
        String(
          format: "| %@ | %.0f | %.0f | %@ |", formatCount(n), rtBuild, sdBuild,
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
        String(
          format: "| %@ | %.0f | %.0f | %@ |", formatCount(n), rtLook, sdLook,
          ratioCell(radix: rtLook, sorted: sdLook)))

      blackHole(rt)
      blackHole(sd)
      print("done n=\(n)")
    }

    var md = ""
    md += "# RadixTree vs SortedDictionary — shared-prefix keys (time)\n\n"
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
