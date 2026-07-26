# Thread Safety Documentation for Swift ART

## Thread Safety Status

**The Adaptive Radix Tree (ART) implementation is NOT thread-safe.**

### Current Behavior

- **Concurrent Reads**: NOT SAFE - Even read operations check for uniqueness (`isKnownUniquelyReferenced`) which can race
- **Concurrent Writes**: NOT SAFE - Will cause data corruption and crashes
- **Read During Write**: NOT SAFE - May see inconsistent state or crash

### Copy-on-Write Semantics

This implementation uses Swift's copy-on-write (COW) semantics:
- Each instance of `RadixTree` or `ARTree` has value semantics
- Copies share the underlying tree structure until a mutation occurs
- When mutation happens, the tree checks uniqueness and clones if needed

### Safe Usage Patterns

#### 1. Single Thread per Tree Instance
```swift
// Each thread gets its own copy
let sharedTree = RadixTree<String, Int>()

DispatchQueue.concurrent.async {
    var localTree = sharedTree  // Makes a COW copy
    localTree["key"] = 42       // Safe - only this thread mutates
}
```

#### 2. Synchronization Required for Shared Access
```swift
class ThreadSafeRadixTree<Key: ConvertibleToBinaryComparableBytes, Value> {
    private var tree = RadixTree<Key, Value>()
    private let queue = DispatchQueue(label: "tree.sync")

    func get(_ key: Key) -> Value? {
        queue.sync { tree[key] }
    }

    func set(_ key: Key, value: Value) {
        queue.async(flags: .barrier) {
            self.tree[key] = value
        }
    }
}
```

#### 3. Actor-Based Concurrency (Swift 5.5+)
```swift
actor SafeRadixTree<Key: ConvertibleToBinaryComparableBytes, Value> {
    private var tree = RadixTree<Key, Value>()

    func get(_ key: Key) -> Value? {
        tree[key]
    }

    func set(_ key: Key, value: Value) {
        tree[key] = value
    }
}
```

### Implementation Details

The lack of thread safety stems from:

1. **Uniqueness Checking**: Operations use `isKnownUniquelyReferenced` which isn't thread-safe
2. **Multi-Step Mutations**: Insert/delete operations involve multiple steps that must be atomic
3. **Shared Buffer Access**: The `ManagedBuffer` backing storage isn't protected

### Future Considerations

Making the tree thread-safe would require either:
- Adding locks around all operations (performance impact)
- Creating a concurrent variant with fine-grained locking
- Using lock-free algorithms (significant redesign required)

For now, users must handle synchronization at the application level.