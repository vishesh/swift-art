import ARTreeModule
import CollectionsBenchmark
import Foundation
import HashTreeCollections

#if UnstableSortedCollections
  import SortedCollections
#endif

// Custom modes that bypass the CollectionsBenchmark CLI.
switch CommandLine.arguments.dropFirst().first {
case "shared-prefix":
  let out = CommandLine.arguments.dropFirst(2).first ?? "Results/shared-prefix.md"
  runSharedPrefixReport(outputPath: out)
  exit(0)
case "memory":
  let out = CommandLine.arguments.dropFirst(2).first ?? "Results/memory.md"
  runMemoryReport(outputPath: out)
  exit(0)
case "range":
  let out = CommandLine.arguments.dropFirst(2).first ?? "Results/range.md"
  runRangeReport(outputPath: out)
  exit(0)
case "profile":
  let args = Array(CommandLine.arguments.dropFirst(2))
  let op = args.first ?? "build"
  let n = args.count > 1 ? Int(args[1]) ?? 1_000_000 : 1_000_000
  let seconds = args.count > 2 ? Double(args[2]) ?? 10 : 10
  runProfile(op: op, n: n, seconds: seconds)
  exit(0)
default:
  break
}

var benchmark = Benchmark(title: "swift-art: RadixTree vs swift-collections")

// MARK: - RadixTree (this package: ordered, persistent radix tree)

addIntMapBenchmarks(
  to: &benchmark, name: "RadixTree",
  empty: { RadixTree<Int, Int>() },
  insert: { $0[$1] = $2 },
  lookup: { $0[$1] },
  remove: { $0[$1] = nil },
  iterate: { for e in $0 { blackHole(e) } },
  count: { $0.reduce(into: 0) { n, _ in n += 1 } })

addStringMapBenchmarks(
  to: &benchmark, name: "RadixTree",
  empty: { RadixTree<String, Int>() },
  insert: { $0[$1] = $2 },
  lookup: { $0[$1] },
  iterate: { for e in $0 { blackHole(e) } })

// MARK: - Dictionary (stdlib: unordered hash map — the universal control)

addIntMapBenchmarks(
  to: &benchmark, name: "Dictionary",
  empty: { [Int: Int]() },
  insert: { $0[$1] = $2 },
  lookup: { $0[$1] },
  remove: { $0[$1] = nil },
  iterate: { for e in $0 { blackHole(e) } },
  count: { $0.count })

addStringMapBenchmarks(
  to: &benchmark, name: "Dictionary",
  empty: { [String: Int]() },
  insert: { $0[$1] = $2 },
  lookup: { $0[$1] },
  iterate: { for e in $0 { blackHole(e) } })

// MARK: - TreeDictionary (swift-collections: unordered, persistent CHAMP)

addIntMapBenchmarks(
  to: &benchmark, name: "TreeDictionary",
  empty: { TreeDictionary<Int, Int>() },
  insert: { $0[$1] = $2 },
  lookup: { $0[$1] },
  remove: { $0[$1] = nil },
  iterate: { for e in $0 { blackHole(e) } },
  count: { $0.count })

addStringMapBenchmarks(
  to: &benchmark, name: "TreeDictionary",
  empty: { TreeDictionary<String, Int>() },
  insert: { $0[$1] = $2 },
  lookup: { $0[$1] },
  iterate: { for e in $0 { blackHole(e) } })

// MARK: - SortedDictionary (swift-collections: ordered B-tree — the true peer)

#if UnstableSortedCollections
  addIntMapBenchmarks(
    to: &benchmark, name: "SortedDictionary",
    empty: { SortedDictionary<Int, Int>() },
    insert: { $0[$1] = $2 },
    lookup: { $0[$1] },
    remove: { $0[$1] = nil },
    iterate: { for e in $0 { blackHole(e) } },
    count: { $0.count })

  addStringMapBenchmarks(
    to: &benchmark, name: "SortedDictionary",
    empty: { SortedDictionary<String, Int>() },
    insert: { $0[$1] = $2 },
    lookup: { $0[$1] },
    iterate: { for e in $0 { blackHole(e) } })
#endif

benchmark.main()
