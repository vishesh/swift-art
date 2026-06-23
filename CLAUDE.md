# CLAUDE.md

Adaptive Radix Tree (ART): a persistent, copy-on-write ordered map. Public API
is `RadixTree<Key, Value>`; the engine is `ARTreeImpl`. Keys must be prefix-free
(`ConvertibleToBinaryComparableBytes` — null-terminated strings, fixed-width
big-endian integers).

## Build & test

Tests use **swift-testing** (`import Testing`, `@Test`/`@Suite`), not XCTest.
They need the **Xcode toolchain** — bare CommandLineTools can't resolve
`Testing`:

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

(Or run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` once,
then plain `swift test`.) Tools-version 6.0, Swift 6 language mode. Assertion
helpers (`expectEqual`, `expectTrue`, …) live in `_CollectionsTestSupport`.

## Simulation testing

`Tests/ARTreeModuleTests/Simulation/` holds a deterministic simulation harness:
it drives long randomized op sequences against the engine (`ARTree<[UInt8]>`),
mirrors each op into a dictionary model, takes/forks/restores live copies to
stress copy-on-write, and checks contents + internal structure + (via
`LifetimeTracked`) that nothing leaks. Seeded by a self-contained `SplitMix64`
(`DeterministicRNG.swift`) — not `RepeatableRandomNumberGenerator`, whose
`42.hashValue` seed isn't reproducible across runs. The COW suite runs with
snapshots (no `.checksUniquePath`); the single-owner suite runs with it.
`COWRegressionTests.swift` pins the specific COW/refcount bugs the harness
found. Opt-in soak: `ART_SIM_STEPS=… ART_SIM_SEEDS=… swift test --filter
ARTreeSoakTests`.

## Conventions

- Comments: brief, only the non-obvious — no restating code or history.
- Commit messages: short and simple. Do not add an AI co-author trailer.

## Gotchas

- `Const.testCheckUnique` is a `@TaskLocal` bound per-test by the
  `.checksUniquePath` trait (`Tests/ARTreeModuleTests/UniquePathTrait.swift`) on
  the Insert/Delete suites. It keeps the unique-path assertion parallel-safe —
  don't revert it to a plain global.
- Some `TreeRefCountTests` assert exact `_getRetainCount` values; these are
  toolchain-fragile. Prefer `isKnownUniquelyReferenced` for COW checks.
