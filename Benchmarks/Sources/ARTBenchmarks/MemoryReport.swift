//===----------------------------------------------------------------------===//
//
// Memory-usage comparison of RadixTree against SortedDictionary on shared-prefix
// keys. For each size it builds one map and attributes the process footprint
// delta (after build minus a baseline taken with the key array already live) to
// that map — i.e. bytes to store n (key, value) pairs in the structure. Run with:
//
//   ARTBenchmarks memory [out.md]
//
//===----------------------------------------------------------------------===//

import ARTreeModule

#if UnstableSortedCollections
  import SortedCollections
#endif

// Build a map (only it is live at the measurement) and return the footprint it
// added, in bytes. `base` is sampled after the key array exists, so the array is
// excluded and we capture the map's own allocations (nodes + its key copies).
@inline(never)
private func radixFootprint(_ n: Int, _ keys: [String]) -> UInt64 {
  let base = physFootprint()
  var m = RadixTree<String, Int>()
  for i in 0..<n { m[keys[i]] = i }
  let used = physFootprint() &- base
  withExtendedLifetime(m) {}
  return used
}

#if UnstableSortedCollections
  @inline(never)
  private func sortedFootprint(_ n: Int, _ keys: [String]) -> UInt64 {
    let base = physFootprint()
    var m = SortedDictionary<String, Int>()
    for i in 0..<n { m[keys[i]] = i }
    let used = physFootprint() &- base
    withExtendedLifetime(m) {}
    return used
  }
#endif

public func runMemoryReport(outputPath: String) {
  #if !UnstableSortedCollections
    print("memory requires the UnstableSortedCollections trait (SortedDictionary).")
    return
  #else
    let sizes = [64_000, 256_000, 1_000_000]
    var rows: [String] = []

    for n in sizes {
      let keys = makeSharedPrefixKeys(n)
      // Measure each map alone; the previous one is released first so its memory
      // doesn't count against the next baseline.
      let rt = radixFootprint(n, keys)
      let sd = sortedFootprint(n, keys)
      let rtPer = Double(rt) / Double(n)
      let sdPer = Double(sd) / Double(n)
      let ratio: String
      if rtPer <= sdPer {
        ratio = String(format: "**%.2f× smaller**", sdPer / rtPer)
      } else {
        ratio = String(format: "%.2f× larger", rtPer / sdPer)
      }
      rows.append(
        String(
          format: "| %@ | %.1f | %.1f | %@ |", formatCount(n), rtPer, sdPer, ratio))
      print("done n=\(n): RadixTree \(rt / 1_048_576) MiB, SortedDictionary \(sd / 1_048_576) MiB")
    }

    var md = ""
    md += "# RadixTree vs SortedDictionary — memory (shared-prefix keys)\n\n"
    md += "Bytes **per element** to store n `(String, Int)` pairs, measured as the "
    md += "process footprint delta after building each map (the source key array is "
    md += "excluded from the baseline). Keys share a long prefix (~80 bytes). "
    md += "Footprint is page-granular and includes the allocator's retained free "
    md += "pages, so treat these as approximate but directly comparable.\n\n"
    md += "| n | RadixTree (B/elem) | SortedDictionary (B/elem) | RadixTree vs SortedDict |\n"
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
