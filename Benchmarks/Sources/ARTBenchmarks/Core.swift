import CollectionsBenchmark

/// Maps an integer to a long, common-prefix string key. The shared prefix is
/// the radix tree's sweet spot and the worst case for comparison- and
/// hash-based maps (long prefixes make `<` and hashing do more work).
@inline(__always)
func prefixedKey(_ i: Int) -> String {
  let s = String(i)
  let pad = String(repeating: "0", count: Swift.max(0, 12 - s.count))
  return "https://example.com/api/v1/resource/" + pad + s
}

/// Registers the integer-keyed suite for one map type `M`, driven entirely by
/// the supplied closures. Every contender exposes the same operations, so this
/// keeps the four implementations honestly identical and makes adding a new one
/// a matter of a few closures (see `main.swift`).
///
/// The built-in `[Int]` generator yields a shuffled `0..<size` permutation;
/// `([Int], [Int])` adds a shuffled lookup key set. So keys are a *dense*
/// integer space inserted in random order — vary key shape via the string suite
/// (shared prefixes) and, later, custom generators for sparse/random keys.
func addIntMapBenchmarks<M>(
  to benchmark: inout Benchmark,
  name: String,
  empty: @escaping () -> M,
  insert: @escaping (inout M, Int, Int) -> Void,
  lookup: @escaping (M, Int) -> Int?,
  remove: @escaping (inout M, Int) -> Void,
  iterate: @escaping (M) -> Void,
  count: @escaping (M) -> Int
) {
  benchmark.add(
    title: "\(name)<Int, Int> build, subscript",
    input: [Int].self
  ) { input in
    return { timer in
      var m = empty()
      for k in input { insert(&m, k, 2 * k) }
      blackHole(m)
    }
  }

  benchmark.add(
    title: "\(name)<Int, Int> lookups, hit",
    input: ([Int], [Int]).self
  ) { input, lookups in
    var m = empty()
    for k in input { insert(&m, k, 2 * k) }
    return { timer in
      for k in lookups { precondition(lookup(m, k) == 2 * k) }
    }
  }

  benchmark.add(
    title: "\(name)<Int, Int> lookups, miss",
    input: ([Int], [Int]).self
  ) { input, lookups in
    var m = empty()
    for k in input { insert(&m, k, 2 * k) }
    let c = input.count
    return { timer in
      for k in lookups { precondition(lookup(m, k + c) == nil) }
    }
  }

  benchmark.add(
    title: "\(name)<Int, Int> sequential iteration",
    input: [Int].self
  ) { input in
    var m = empty()
    for k in input { insert(&m, k, 2 * k) }
    return { timer in
      iterate(m)
    }
  }

  benchmark.add(
    title: "\(name)<Int, Int> remove all",
    input: ([Int], [Int]).self
  ) { input, lookups in
    return { timer in
      var m = empty()
      for k in input { insert(&m, k, 2 * k) }
      timer.measure {
        for k in lookups { remove(&m, k) }
      }
      precondition(count(m) == 0)
      blackHole(m)
    }
  }

  // The headline persistence benchmark. Each iteration forks the whole map and
  // inserts one fresh key while the original stays alive. Persistent structures
  // (RadixTree, TreeDictionary, SortedDictionary) share structure, so per-op
  // cost grows sub-linearly; `Dictionary` copies its whole buffer on first
  // mutation, so this is O(n) per op — O(n^2) total. Run with a modest
  // `--max-size` (e.g. 16384) or `Dictionary` dominates the wall clock.
  benchmark.add(
    title: "\(name)<Int, Int> fork + insert one",
    input: [Int].self
  ) { input in
    var base = empty()
    for k in input { insert(&base, k, 2 * k) }
    let c = input.count
    return { timer in
      for k in input {
        var copy = base
        insert(&copy, k + c, 0)
        blackHole(copy)
      }
      blackHole(base)
    }
  }
}

/// Registers the String-keyed suite using long common-prefix keys — the case
/// the radix tree is built for.
func addStringMapBenchmarks<M>(
  to benchmark: inout Benchmark,
  name: String,
  empty: @escaping () -> M,
  insert: @escaping (inout M, String, Int) -> Void,
  lookup: @escaping (M, String) -> Int?,
  iterate: @escaping (M) -> Void
) {
  benchmark.add(
    title: "\(name)<String, Int> build, shared-prefix keys",
    input: [Int].self
  ) { input in
    let keys = input.map { prefixedKey($0) }
    return { timer in
      var m = empty()
      for (i, key) in keys.enumerated() { insert(&m, key, i) }
      blackHole(m)
    }
  }

  benchmark.add(
    title: "\(name)<String, Int> lookups, hit, shared-prefix keys",
    input: ([Int], [Int]).self
  ) { input, lookups in
    var m = empty()
    for k in input { insert(&m, prefixedKey(k), k) }
    let lookupKeys = lookups.map { prefixedKey($0) }
    return { timer in
      for key in lookupKeys { blackHole(lookup(m, key)) }
    }
  }

  benchmark.add(
    title: "\(name)<String, Int> sequential iteration, shared-prefix keys",
    input: [Int].self
  ) { input in
    var m = empty()
    for k in input { insert(&m, prefixedKey(k), k) }
    return { timer in
      iterate(m)
    }
  }
}
