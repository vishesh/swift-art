# Closing the gap with swift-collections: analysis & rearchitecture plan

## Context

After a round of constant-factor optimizations (allocation-free insert/delete, SIMD Node16,
ARC-free reads, iteration rewrite, move-on-grow), `RadixTree` is still **~4–8× slower on point ops
and ~3× larger in memory** than swift-collections' `SortedDictionary` (B-tree) and `TreeDictionary`
(CHAMP). That earlier work removed *incidental* overhead; what remains is **structural**. This
document records why, and what it would take to close it — including a major rearchitecture, since
the dominant cause is a design choice.

Measured (per element, n = 16384–4M, release):

- Int lookup ~6.8×, int build ~8×, remove ~6×, string lookup ~4.4× slower vs `SortedDictionary`.
- Memory ~3.0× larger (≈112 B/elem vs ≈37 B/elem for `(String, Int)` shared-prefix keys).
- Build profile: dominated by `malloc`/`free` + `swift_retain`/`swift_release`.

## Root cause: allocation granularity

The single dominant difference, confirmed by reading both swift-collections engines:

| | This ART | SortedDictionary (B-tree) | TreeDictionary (CHAMP) |
|---|---|---|---|
| Heap objects for N items | **O(N)** — one leaf per key **+** internal nodes | O(N / ~250) leaf nodes | O(N / ~16–32) nodes |
| Entries per allocation | **1** (leaf) | ~250 leaf / ~16 internal (cache-tuned) | up to 32, bitmap-packed |
| Node storage | `ManagedBuffer` per node, closure-layered access | one buffer, **contiguous** keys (tail-alloc), binary search | one buffer, **bitmap + compact array**, popcount index |
| Traversal | pointer-chase scattered small nodes | `Unmanaged` walk, ~2–3 nodes for 1M | `Unmanaged` walk, ~2–3 nodes for 1M |
| Key bytes | **copied raw into every leaf** (no COW share) | `Comparable` key struct, COW-shared buffer | `Hashable` key struct, COW-shared buffer |

Everything else follows from this:

1. **Build is malloc/ARC-bound** — we create and refcount O(N) class objects; they create
   O(N/fanout). That is the profile (malloc + free + retain + release dominate), not a fixable constant.
2. **Lookups pointer-chase** scattered small allocations (a cache miss per hop), and byte-granular
   keys need more hops; B-tree/CHAMP touch 2–3 contiguous, prefetch-friendly nodes.
3. **Memory ~3×** — a `ManagedBuffer` object header per node spread over **1** entry vs 16–250; plus
   we materialize full key bytes per leaf (optimistic compression stores the whole key in the leaf)
   while the others keep a 16-byte `String` struct sharing one COW buffer.
4. **Node48/Node256 are sparse** — a 256-byte index table / 2 KB pointer array per node.
5. **Per-hop access is closure-layered** (`withBodyPointer` → `withRaw` → `_withUnsafeGuaranteedRef`
   → `withUnsafeMutablePointerToElements`); swift-collections use a direct `UnsafeHandle` over the buffer.

**Honest verdict:** a byte-granular, one-leaf-per-key radix tree will **not** match a cache-tuned
B-tree/CHAMP on pure point ops + memory, no matter how much we micro-optimize. The gap is the data
model. ART's genuine edge is **prefix/range/ordered scans over shared-prefix keys** — which aren't
even exposed in the public API yet, so the structure is currently judged only on its weakest axis.

## What swift-collections does that we should adopt

- **Pack many entries per allocation** (the big one) — B-tree leaf ≈250, CHAMP ≈32.
- **Contiguous in-buffer storage + direct `UnsafeHandle`** (no closure layering), binary search /
  popcount within a node.
- **`Unmanaged` traversal** (already done for `getValue`; extend to insert/delete/iterate).
- **Bulk `moveInitialize`** for splits/shifts; **in-place COW** (`ensureUnique`) mutation.
- **Cache-tuned fanout** (size nodes to L1/L2, not arbitrary 4/16/48/256).

## Primary lever: multi-entry (bucketed) leaves

Replace one-leaf-per-key with **B-tree-style leaf chunks**: the trie routes on prefix bytes down to a
leaf that holds a **sorted array of (key-suffix, value) entries** (capacity ~16–32 in one buffer); a
chunk splits into trie structure only on overflow. This directly attacks the #1 cause:

- Leaf allocations: **O(N) → O(N/chunk)** → build malloc/ARC and memory drop ~chunk-fold.
- Lookups: descend the (now shallower) trie to a leaf, then binary-search a contiguous chunk (few
  cache lines) instead of bottoming out at scattered single-key leaves.
- Keeps ART's identity (prefix routing) while borrowing the B-tree's packing for the hot bottom level.

This is a **significant rearchitecture** of `NodeLeaf`, `getValue`/insert/delete/iterate, and the
simulation/COW harness expectations — but it is the only thing that moves the structural needle.

**Alternatives considered (not the primary path):**

- *Pessimistic compression + tagged/value-only leaves* — eliminates per-key key storage and can
  inline word-sized values, but leaves the low-fanout internal-node allocation count and bloats
  long-unique-suffix keys; smaller payoff than bucketed leaves.
- *Incremental tightening only* (cache the body pointer, shrink Node48/256, direct `UnsafeHandle`) —
  worth doing but cannot close a structural, allocation-granularity gap.
- *Replace the engine with a B-tree/CHAMP* — that abandons the radix tree; swift-collections already
  ships both.

## Direction: both workstreams

Pursue the structural rearchitecture **and** expose the operations a radix tree wins at. Both are
large; land each phase incrementally behind the existing test/COW/simulation harness (debug + release
+ soak) before moving on.

### Workstream 1 — Multi-entry (bucketed) leaves *(the gap-closer; do first)*

1. Add a multi-entry leaf node: one buffer holding a **sorted array of (key-suffix, value)** entries,
   capacity ~16–32, binary-searched within. Replaces one-leaf-per-key.
2. Route the trie down to a leaf bucket; **split** a bucket into trie structure only on overflow,
   **merge** on underflow. Keeps prefix routing; packs the hot bottom level.
3. Adopt swift-collections' storage discipline: direct `UnsafeHandle` over the buffer (drop the
   `withBodyPointer` → `withRaw` → … closure layering), `Unmanaged` traversal on insert/delete/iterate
   (reads already done), bulk `moveInitialize` for shifts/splits, in-place COW (`ensureUnique`).
4. Re-tune the node set / fanout to cache size; shrink Node48 (256-byte table) and Node256 (2 KB) waste.

### Workstream 2 — Prefix/range API *(play to strengths)*

5. Implement `entries(withPrefix:)` and `getRange(start:end:)` (currently `fatalError`).
6. Add prefix/range scan benchmarks (extend `ARTBenchmarks`) to show where RadixTree beats the B-tree.

### Sequencing & expectations

- Workstream 1 first — it attacks the dominant cost (O(N) allocations → O(N/chunk)). Realistic target:
  narrow point ops from ~5–8× to ~1.5–2× and memory from ~3× toward parity; full point-op parity with
  a B-tree is unlikely for a byte-trie and is not the bar.
- Workstream 2 can proceed in parallel; it is where the structure should clearly win.

## Verification

- Full suite green in debug **and** `swift test -c release`, including the COW/simulation harness and
  the deterministic soak (`ART_SIM_STEPS=… ART_SIM_SEEDS=…`).
- Re-run `ARTBenchmarks shared-prefix`, `memory`, and the full suite vs `main`; compare per-element
  time and bytes/element.
- Profile build/lookup (`scripts/profile.sh`) to confirm malloc/ARC traffic dropped.
