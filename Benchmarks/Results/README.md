# Benchmark results

A snapshot comparing `RadixTree` against `Dictionary` (stdlib), `TreeDictionary`
and `SortedDictionary` (swift-collections). Charts are log-log: x = element
count (1 → 64k), y = **per-element** time (lower is faster). `results.json` is
the raw data — re-render any view with `ARTBenchmarks render results.json out.png --filter <regex>`.

- **Machine:** Apple Silicon, macOS 26, release build (`-c release`).
- **Run:** `ARTBenchmarks run results.json --cycles 3 --max-size 65536`
- Int keys: shuffled `0..<n` (dense). String keys: long common-prefix.

| Chart | Operation |
|---|---|
| `int-build.png` | insert n int keys via subscript |
| `int-lookup-hit.png` | successful point lookups |
| `int-iteration.png` | full in-order scan |
| `fork-insert.png` | snapshot the map + insert one key, original kept alive |
| `string-build-shared-prefix.png` | insert n shared-prefix string keys |
| `string-lookup-shared-prefix.png` | successful lookups, shared-prefix keys |

## Takeaways

- `RadixTree` is currently **10–100× slower than all three** on every operation
  at these sizes — including shared-prefix string keys, its intended sweet spot.
- Its curves are **flat**: the complexity class is fine, the problem is a large
  **constant factor** — most likely the per-op `[UInt8]` allocation in
  `toBinaryComparableBytes()` / `fromBinaryComparableBytes()`.
- `fork-insert` confirms the persistence property works (flat, and it overtakes
  `Dictionary`'s O(n) copy around ~16k) — but `TreeDictionary`/`SortedDictionary`
  are flat *and* far cheaper.
- The only narrowing gap is `string-lookup` at large n, where `SortedDictionary`
  pays growing long-prefix comparison costs while `RadixTree` stays flat.

These are point-op workloads where a hash map should win. The comparison that
would actually favor a radix tree — range/prefix scans — isn't in the public
API yet. See `../README.md` for caveats and next steps.
