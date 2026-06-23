# swift-art

An Adaptive Radix Tree (ART)[^art] implementation in Swift. ART is a trie-based
data structure that provides ordered key-value storage with efficient lookup,
insertion, and deletion. It uses path compression and lazy expansion to keep
memory usage low while maintaining performance comparable to hash tables.

## Requirements

- Swift 6.0+

## Usage

In your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/your-org/swift-art", from: "0.1.0"),
],
targets: [
    .target(name: "MyTarget", dependencies: [
        .product(name: "ARTreeModule", package: "swift-art"),
    ]),
]
```

### Example

```swift
import ARTreeModule

// ARTree keyed on raw bytes
var tree = ARTree<Int>()
tree.insert(key: [1, 2, 3], value: 42)
let value = tree.getValue(key: [1, 2, 3])  // Optional(42)
tree.delete(key: [1, 2, 3])

// RadixTree keyed on String (or any type with a byte representation)
var dict: RadixTree<String, Int> = [:]
dict["hello"] = 1
dict["world"] = 2
for (key, value) in dict {
    print(key, value)
}
```

## Development

```
swift build
```

### Testing

On macOS, Xcode must be installed and selected as the active developer directory:

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

## References

[^art]: V. Leis, A. Kemper, and T. Neumann,
"The Adaptive Radix Tree: ARTful Indexing for Main-Memory Databases,"
ICDE 2013, pp. 38–49.
DOI: https://doi.org/10.1109/ICDE.2013.6544812
