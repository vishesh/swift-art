# Benchmarks

Performance comparison of `RadixTree` against the maps people would realistically
reach for. Kept as a **separate package** so the main library product stays
dependency-free — nothing here is pulled into consumers of `ARTreeModule`.

## Contenders

| Map | Source | Category | Role |
|---|---|---|---|
| `RadixTree` | this package | ordered, persistent (COW) radix tree | subject under test |
| `Dictionary` | stdlib | unordered hash map, COW | universal control; fastest point ops |
| `TreeDictionary` | swift-collections (CHAMP) | unordered, **persistent** | peer for the persistence story |
| `SortedDictionary` | swift-collections (B-tree) | **ordered**, COW | the true ordered-map peer |

`SortedDictionary` lives behind swift-collections' `UnstableSortedCollections`
package trait (an explicitly-labeled *prototype* — "not ready for production,
source-breaking API changes before they ship"). This package enables that trait
by default and pins an exact swift-collections version in `Package.resolved`.
Treat its numbers as "vs the current prototype B-tree" and re-run when it
stabilizes.

## Running

Always build in **release** — debug numbers are meaningless.

```sh
# from this directory
swift build -c release
.build/release/ARTBenchmarks info --tasks          # list the 36 tasks
.build/release/ARTBenchmarks run results.json --cycles 1
```

On macOS the Xcode toolchain is required (same as the test suite):

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build -c release
```

Useful `run` flags: `--max-size`, `--min-size`, `--cycles`, `--filter <regex>`,
`-n/--dry-run`. Re-running appends to the results file, so repeated `--cycles`
accumulate samples; the harness reports per-element time bands (min/mean/median).

### Rendering charts

```sh
.build/release/ARTBenchmarks render results.json chart.png --filter "fork"
```

Charts are log-log: x = input size, y = **per-element** processing time. Flat
lines mean linear scaling; an upward slope means super-linear per element.

## What's measured

Nine tasks per contender. Integer keys use the harness's built-in generators
(a shuffled `0..<size` permutation, i.e. a *dense* key space inserted in random
order); string keys use long, common-prefix keys — the radix tree's sweet spot:

- build (subscript), lookups hit/miss, sequential iteration, remove-all
- **fork + insert one** — the persistence headline: snapshot the whole map,
  insert one fresh key, keep the original alive. Persistent maps share structure
  (flat per-op cost); `Dictionary` copies its whole buffer (O(n) per op).
- string build / lookup / iteration with shared-prefix keys

## Caveats / things to extend

- **`fork + insert one` is O(n²) total for `Dictionary`** (each of n forks does an
  O(n) copy). Cap it with `--max-size 16384` or `Dictionary` dominates wall time.
- **Key distribution dominates ART's results.** Today we cover dense ints and
  shared-prefix strings. To be honest about worst cases, add custom input
  generators for *sparse/random* integers and *high-entropy* strings (register
  via `benchmark.registerInputGenerator(for:)`).
- **Key-conversion cost is included.** `RadixTree` allocates a `[UInt8]` per op
  in `toBinaryComparableBytes()`. That's a real cost of the public API, but to
  isolate the tree from the encoding, also benchmark the raw `ARTree<Value>`
  engine on pre-encoded bytes (not yet wired up here).
- **Range/prefix queries** — ART's biggest theoretical advantage — aren't in the
  public `RadixTree` API yet, so they aren't benchmarked. Add them once exposed.

## Note for maintainers

Building `ARTreeModule` in release first surfaced two issues, now fixed in the
library: a `default` case that fell through without returning once `assert` was
stripped (`RawNode.swift`), and a Swift 6.3.2 optimizer crash in `StackPromotion`
worked around with `@_optimize(none)` on `NodeStorage.create` (`NodeStorage.swift`).
The library had only ever been built in debug before this.
