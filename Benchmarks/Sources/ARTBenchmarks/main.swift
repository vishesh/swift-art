import CollectionsBenchmark
import ARTreeModule
import HashTreeCollections
#if UnstableSortedCollections
import SortedCollections
#endif

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
  empty: { Dictionary<Int, Int>() },
  insert: { $0[$1] = $2 },
  lookup: { $0[$1] },
  remove: { $0[$1] = nil },
  iterate: { for e in $0 { blackHole(e) } },
  count: { $0.count })

addStringMapBenchmarks(
  to: &benchmark, name: "Dictionary",
  empty: { Dictionary<String, Int>() },
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
