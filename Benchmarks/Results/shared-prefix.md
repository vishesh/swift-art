# RadixTree vs SortedDictionary — shared-prefix keys

Keys are a long, deeply-namespaced shared prefix (~80 bytes) followed by a zero-padded counter, so they differ only near the end. This is the radix tree's intended sweet spot and the worst case for a comparison-based B-tree, whose every key comparison must rescan the shared prefix.

Times are **per-element** in nanoseconds (lower is faster); the last column compares `RadixTree` to `SortedDictionary` from swift-collections. Apple Silicon, `-c release`, min of 3 runs.

## Lookup (successful)

| n | RadixTree (ns) | SortedDictionary (ns) | RadixTree vs SortedDict |
|--:|--:|--:|:--|
| 1k | 2059 | 154 | 13.34× slower |
| 4k | 1464 | 173 | 8.47× slower |
| 16k | 1564 | 241 | 6.49× slower |
| 64k | 1734 | 300 | 5.78× slower |
| 256k | 1911 | 554 | 3.45× slower |
| 1M | 1999 | 904 | 2.21× slower |
| 4M | 2163 | 1223 | 1.77× slower |

## Build (insert n keys)

| n | RadixTree (ns) | SortedDictionary (ns) | RadixTree vs SortedDict |
|--:|--:|--:|:--|
| 1k | 4130 | 143 | 28.79× slower |
| 4k | 2457 | 119 | 20.56× slower |
| 16k | 2450 | 140 | 17.48× slower |
| 64k | 2513 | 173 | 14.50× slower |
| 256k | 2570 | 198 | 12.98× slower |
| 1M | 2637 | 264 | 9.97× slower |
| 4M | 2726 | 445 | 6.12× slower |
