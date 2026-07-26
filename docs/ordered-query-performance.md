# Where RadixTree wins, and what we did about it

A follow-up to `performance-rearchitecture.md`. That doc concluded the point-op /
memory gap vs swift-collections is **structural** (one heap allocation per key)
and needs a large rewrite. This doc answers a different question the benchmarks
raised — *are we even measuring the right workload?* — and records the work that
followed from the answer.

## The question: is the dataset the problem?

Partly, yes. The suite judges RadixTree on point ops (build/lookup/remove),
memory, and small-window range scans. Those are ART's **weakest** axes, and two
of the contenders (`Dictionary`, `TreeDictionary`) are hash maps that are simply
faster at point ops and denser in memory. Cross-checking against the literature:

- **Range scans vs a B-tree: ART is expected to lose.** "B-Trees Are Back"
  (SIGMOD 2025) measures a tuned B-tree 18–219% faster than tries on scans — a
  B-tree touches ~2 contiguous leaves; a trie walks many scattered nodes. Our
  `range` numbers (RadixTree ~1.7–2× slower than SortedDictionary) match this.
- **Point ops vs a good hash table: ART is expected to lose** (Álvarez et al.,
  ICDE 2015: a tuned hash table ≥2.8× faster on lookups). Our `Dictionary`
  numbers match this.

So ART's genuine, defensible edge — the reason to pick it over these maps — is
**ordered queries** (range, prefix, predecessor/successor, min/max, ordered
iteration), and specifically the **seek**: a radix descent is O(key length),
*independent of n*, whereas a comparison tree pays O(log n) key comparisons that
each re-scan the shared prefix. Against the two hash maps, ordered queries aren't
merely slower — they're **not supported without a full O(n) scan**. That is the
dataset where ART shines, and it was not being measured.

## What we shipped

Two workstreams, both landed behind the existing test / COW / simulation harness
(debug + release green; the deterministic soak passes). Neither touches the
allocation-granularity gap — that is still the structural rewrite below.

### 1. Fast ordered-scan path (constant-factor, but large)

The old range scan rebuilt the accumulated key prefix in a heap `[UInt8]` per
query and re-ran an O(prefix) lexicographic compare at *every* node. Rewrote it
(`ARTree+Range.swift`) as a **boundary-tracked descent**: carry two flags for
whether the path is still flush against the lower / upper bound; a subtree that is
strictly interior to the range is emitted wholesale with **no comparisons**, and
only the two range edges do byte work — against a single bound byte. The prefix
scan (`ARTree+Prefix.swift`) got the same treatment: descend O(prefix) to the one
matching subtree, then emit it with no per-leaf re-check.

Measured (`range`, 32-key window, shared-prefix keys, per query):

| n | before | after | vs SortedDictionary |
|--:|--:|--:|:--|
| 1M | 25417 ns | 10692 ns | 4.0× → 1.7× slower |

Roughly **2.4× faster** scans; the gap to the B-tree narrowed from ~4× to ~1.7×.
The leaf key compare also now starts at the descent depth instead of byte 0
(`ARTree+get.swift`), skipping the already-verified shared prefix — correct and
free, but its wall-clock effect on point lookups is within noise (~2 µs at ≥1M
either way). That confirms the shared-prefix lookup cost is **cache misses down
the node chain**, not byte compares — which is why item 2 below, not this tweak,
is the real lever.

### 2. Expose + benchmark the seek (the operation ART is *for*)

- New API `RadixTree.firstEntry(from:)` — the successor/ceiling ("first key
  ≥ x"), the purest expression of ART's O(k) seek. Built on an early-exiting
  unbounded range visit.
- New `ARTBenchmarks ordered` report — a bounded range scan and a successor seek
  timed against **all four** maps.

Measured (`ordered`, shared-prefix keys, per-query ns). The fair peer is the other
*ordered* map, `SortedDictionary` (B-tree):

| n | range: RadixTree | range: SortedDict | RadixTree vs SortedDict |
|--:|--:|--:|:--|
| 1k | 6992 | 3353 | 2.1× slower |
| 100k | 7478 | 4190 | 1.8× slower |
| 1M | 7419 | 4346 | 1.7× slower |

So against the B-tree, RadixTree **loses** the scan — its seek is flat in n, but the
B-tree walks contiguous leaves while RadixTree walks scattered per-key leaves. ART's
only categorical win is over the **hash** maps (`Dictionary`, `TreeDictionary`),
which have no order and must scan all n: at 1M the range query is ~81× faster and
the successor seek ~9775× faster than `Dictionary` — but that mostly shows a hash
map is the wrong tool for ordered queries, not that RadixTree is fast in absolute
terms. (`SortedDictionary` has no public successor API, so the seek is benchmarked
only against the hash maps; the fair RadixTree-vs-B-tree "locate" number is the
exact point lookup above — ~2.3× slower at 1M.)

## Correctness fixes made alongside

The test suite was not fully green to begin with; fixed while here:

- **Release-only iteration bug (real, in the engine).** `RadixTree.Iterator.next`
  passed `keyBytes.withUnsafeBytes { $0 }` — an escaping buffer pointer — into the
  key decoder. Under `-O` the storage is reused before the decode runs, so
  iteration returned **all-zero keys** (`""`/`Int.min`) with correct values;
  debug happened to leave the memory intact. Fixed to decode the `[UInt8]`
  directly. Only `swift test -c release` caught this.
- **Two node-shrink tests** asserted an eager shrink; corrected to the actual
  hysteresis thresholds (Node16→Node4 at 3, Node48→Node16 at 13).
- **A prefix-scan test** inserted a key that was a prefix of another (violates the
  prefix-free contract → OOB in `insert`); gave it a prefix-free distractor and
  added a debug `assert` so the contract fails clearly instead of via a buffer
  overrun.

Full suite is now green in **both** debug and release (192 tests).

## What's left (the structural gap — unchanged)

Point-op throughput and memory still need the rewrite from
`performance-rearchitecture.md`. In priority order, informed by how production
ARTs (DuckDB, libart, the paper) do it:

1. **Combined pointer/value slots (leaf inlining).** When a value fits in a
   pointer word, store it inline in the parent's child slot with a tag bit — no
   leaf allocation at all. DuckDB's PR #8112 reports this removes one node per
   lookup and ~1.6 MB per 100k keys. Biggest bang for the least structural risk.
2. **Optimistic path compression.** Today a prefix longer than 8 bytes becomes a
   *chain* of single-child nodes (a cache miss per hop); an ~80-byte shared prefix
   is ~10 nodes. Real ART stores the skip *count* and only 8 bytes, skips the
   rest, and verifies once at the leaf — collapsing the chain to one node. This is
   what keeps our shared-prefix lookup constant (~2 µs) high.
3. **Bucketed (multi-entry) leaves.** The O(N)→O(N/chunk) allocation win. Note: a
   first attempt was reverted (`git log`) for Collection-conformance / iterator
   instability — needs a from-scratch design with stable storage.

Sources: ART paper https://db.in.tum.de/~leis/papers/ART.pdf · DuckDB
https://duckdb.org/2022/07/27/art-storage , PR #8112 · libart
https://github.com/armon/libart · "B-Trees Are Back" (SIGMOD 2025) · Álvarez et
al., ICDE 2015 (ART vs hash tables).
