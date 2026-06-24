# Benchmarks

Performance comparison of `RadixTree` against the maps people would realistically
reach for. Kept as a **separate package** so the main library product stays
dependency-free — nothing here is pulled into consumers of `ARTreeModule`.

**Results are not checked in.** Regenerate them locally with the commands below;
everything under `Results/` and any `*.trace` bundle is gitignored.

## Contenders

| Map | Source | Category | Role |
|---|---|---|---|
| `RadixTree` | this package | ordered, persistent (COW) radix tree | subject under test |
| `Dictionary` | stdlib | unordered hash map, COW | universal control; fastest point ops |
| `TreeDictionary` | swift-collections (CHAMP) | unordered, **persistent** | peer for the persistence story |
| `SortedDictionary` | swift-collections (B-tree) | **ordered**, COW | the true ordered-map peer |

`SortedDictionary` lives behind swift-collections' `UnstableSortedCollections`
trait (an explicitly-labeled prototype). This package enables it by default and
pins an exact version in `Package.resolved`; treat its numbers as "vs the current
prototype B-tree."

## Setup

Always build in **release** — debug numbers are meaningless. On macOS the Xcode
toolchain is required (same as the test suite). All commands below run from this
`Benchmarks/` directory.

```sh
cd Benchmarks
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift build -c release
```

## 1. Comparison suite (time, all contenders)

The swift-collections-benchmark harness over all tasks — build, lookups
(hit/miss), iteration, remove-all, fork+insert — for dense-int and shared-prefix
string keys.

```sh
.build/release/ARTBenchmarks info --tasks                                   # list tasks
.build/release/ARTBenchmarks run Results/results.json --cycles 3 --max-size 65536
.build/release/ARTBenchmarks render Results/results.json Results/lookup.png --filter "lookup, hit"
```

Charts are log-log: x = input size, y = **per-element** time (flat = linear
scaling). `--filter <regex>` selects tasks. `fork + insert one` is O(n²) for
`Dictionary`, so cap it with `--max-size 16384`.

## 2. Focused reports — RadixTree vs SortedDictionary (Markdown)

Self-timed comparisons on the radix tree's sweet spot (long shared-prefix keys),
written as a Markdown table.

```sh
.build/release/ARTBenchmarks shared-prefix Results/shared-prefix.md   # time, swept to 4M
.build/release/ARTBenchmarks memory Results/memory.md                 # memory, bytes/element
```

- **shared-prefix** — per-element lookup and build time. RadixTree's cost is flat
  in `n` while SortedDictionary's grows with `log n × prefix-comparison`.
- **memory** — bytes per element, from the process-footprint delta of building
  each map (page-granular, approximate, but measured identically for both).

## 3. Profiling / flame graphs

`profile <op>` runs one RadixTree operation in a loop for a fixed duration so a
profiler has a stable hot path. `op` ∈ `build | lookup | iterate | delete`.

```sh
.build/release/ARTBenchmarks profile lookup 1000000 15   # op, n, seconds
```

### Instruments — no install; CPU and allocations

```sh
../scripts/profile.sh lookup           # CPU time profile, opens Instruments
../scripts/profile.sh build alloc      # allocation profile
# usage: ../scripts/profile.sh <op> [cpu|alloc] [n] [seconds]
```

In Instruments, invert the Call Tree and "Hide system libraries" for a
flame-graph-style view of the hot path; the **Allocations** instrument shows
where memory is allocated.

### samply — interactive in-browser flame graph (`brew install samply`)

```sh
samply record .build/release/ARTBenchmarks profile lookup 1000000 15
```

Opens the Firefox Profiler with an interactive flame graph, call tree, and stack
chart — the easiest way to explore the hot path.

### sample — quick text call tree, zero setup

```sh
.build/release/ARTBenchmarks profile lookup 1000000 20 &
sample $! 5 -file /tmp/art-cpu.txt && open -e /tmp/art-cpu.txt
```

## Notes / things to extend

- **Key distribution dominates ART's results.** Today we cover dense ints and
  shared-prefix strings; add custom input generators for sparse/random integers
  and high-entropy strings to probe worst cases.
- **Range/prefix queries** — ART's biggest theoretical advantage — aren't in the
  public `RadixTree` API yet, so they aren't benchmarked. Add them once exposed.
- Building `ARTreeModule` in release relies on an `@_optimize(none)` workaround
  on `NodeStorage.create` for a Swift 6.3.2 `StackPromotion` optimizer crash.
