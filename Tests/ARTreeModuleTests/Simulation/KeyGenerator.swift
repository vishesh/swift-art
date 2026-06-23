/// Key-shape presets for the simulation.
enum KeygenKind { case clustered, wide, deep }

/// Generates **prefix-free** `[UInt8]` keys from a seeded RNG.
///
/// The engine requires prefix-free keys for correctness. Two schemes keep that
/// guarantee while still exercising the structure:
/// - `nullTerminated`: body bytes are drawn from `alphabet` (which excludes 0) and a
///   single `0x00` terminator is appended. Varying-length keys stay prefix-free and
///   exercise partial-prefix compression and leaf splits.
/// - fixed width (`!nullTerminated`, `minBodyLen == maxBodyLen`): all keys have the
///   same length, so none can be a prefix of another regardless of byte values —
///   good for wide fan-out (e.g. `Node256`).
///
/// A `prefixPool` of shared leading byte-strings biases keys to share prefixes,
/// driving prefix compression and node splitting.
struct KeyGenerator {
  let alphabet: ClosedRange<UInt8>
  let minBodyLen: Int
  let maxBodyLen: Int
  let prefixPool: [[UInt8]]
  let nullTerminated: Bool

  func makeKey<R: RandomNumberGenerator>(using rng: inout R) -> [UInt8] {
    var key: [UInt8] = []
    if !prefixPool.isEmpty && Bool.random(using: &rng) {
      key = prefixPool[Int.random(in: 0..<prefixPool.count, using: &rng)]
    }

    if nullTerminated {
      let target = Int.random(in: minBodyLen...maxBodyLen, using: &rng)
      while key.count < target {
        key.append(UInt8.random(in: alphabet, using: &rng))
      }
      key.append(0)
      return key
    } else {
      let width = minBodyLen  // == maxBodyLen for fixed-width keys
      if key.count > width { key = Array(key.prefix(width)) }
      while key.count < width {
        key.append(UInt8.random(in: alphabet, using: &rng))
      }
      return key
    }
  }
}

func makeKeyGenerator<R: RandomNumberGenerator>(
  _ kind: KeygenKind,
  using rng: inout R
) -> KeyGenerator {
  switch kind {
  case .clustered:
    // Moderate alphabet, variable length, several shared prefixes.
    let pool = makePrefixPool(count: 6, alphabet: 1...6, lengths: 1...5, using: &rng)
    return KeyGenerator(
      alphabet: 1...6, minBodyLen: 1, maxBodyLen: 14,
      prefixPool: pool, nullTerminated: true)
  case .wide:
    // Fixed 2-byte keys over the full byte range -> wide fan-out, Node256 at root.
    return KeyGenerator(
      alphabet: 0...255, minBodyLen: 2, maxBodyLen: 2,
      prefixPool: [], nullTerminated: false)
  case .deep:
    // Tiny alphabet + long bodies + long shared prefixes -> deep trees, partials
    // that overflow `maxPartialLength` (exercises the single-child merge path).
    let pool = makePrefixPool(count: 4, alphabet: 1...3, lengths: 6...12, using: &rng)
    return KeyGenerator(
      alphabet: 1...3, minBodyLen: 4, maxBodyLen: 24,
      prefixPool: pool, nullTerminated: true)
  }
}

private func makePrefixPool<R: RandomNumberGenerator>(
  count: Int,
  alphabet: ClosedRange<UInt8>,
  lengths: ClosedRange<Int>,
  using rng: inout R
) -> [[UInt8]] {
  var pool: [[UInt8]] = []
  for _ in 0..<count {
    let len = Int.random(in: lengths, using: &rng)
    var p: [UInt8] = []
    for _ in 0..<len { p.append(UInt8.random(in: alphabet, using: &rng)) }
    pool.append(p)
  }
  return pool
}
