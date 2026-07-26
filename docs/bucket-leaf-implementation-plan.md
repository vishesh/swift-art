# Bucket Leaf Implementation Plan

## Overview
The swift-art repository currently has a memory overhead issue with ~62 bytes per entry compared to ~20 bytes for standard dictionaries. The primary cause is that each key-value pair is stored in a separate leaf node with its own memory allocation and reference counting overhead.

## Current State (as of commit 2394db2)
- Bucket leaf implementation has been completely removed due to Collection conformance issues
- All tests are passing with single-entry leaves
- Memory usage: ~62 bytes/entry (3x overhead compared to Dictionary)
- Performance: SIMD optimizations are in place for Node4/16/48

## Problem Analysis

### Memory Overhead Breakdown
For each entry in the current implementation:
1. **NodeLeaf allocation**:
   - ManagedBuffer header: 16 bytes (isa pointer + reference count)
   - NodeType: 1 byte
   - Key storage: variable (typically 8-16 bytes)
   - Value storage: 8 bytes (for Int)
   - Padding/alignment: ~8 bytes
   - **Total**: ~48 bytes per leaf

2. **Parent node slot**:
   - Pointer to leaf: 8 bytes
   - Key byte in parent: 1 byte
   - **Total**: ~9 bytes

3. **Overall**: ~62 bytes per entry

### Root Cause of Collection Failure
The previous bucket leaf implementation failed because:
1. **Iterator instability**: The iterator created temporary NodeBucketLeaf wrappers with unretained references
2. **Count inconsistency**: Collection.count and map() would traverse the tree multiple times, getting different results
3. **Memory management**: Bucket modifications during iteration could invalidate pointers

## Proposed Solution

### Phase 1: Bucket Leaf Design
Create a stable bucket leaf implementation that maintains iterator consistency:

```swift
// NodeBucketLeaf should store entries inline
struct NodeBucketLeaf<Spec: ARTreeSpec> {
    static let capacity = 32

    // Store entries in a single allocation
    struct Entry {
        let keyLength: UInt16
        let key: [UInt8]  // Inline storage
        var value: Spec.Value
    }

    // Use a stable storage mechanism
    class Storage: RawNodeBuffer {
        var count: Int
        var entries: [Entry]  // Fixed-size array

        // Maintain stable iteration order
        func withStableEntries<R>(_ body: (UnsafeBufferPointer<Entry>) -> R) -> R
    }
}
```

### Phase 2: Iterator Stability
Ensure the iterator produces consistent results across multiple traversals:

1. **Snapshot bucket state**: When starting iteration on a bucket, capture the count
2. **Validate consistency**: Check that bucket hasn't been modified during iteration
3. **COW for modifications**: Any bucket modification during iteration creates a new copy

```swift
extension ARTreeImpl._Iterator {
    // Store bucket snapshot for stable iteration
    struct BucketSnapshot {
        let node: RawNode
        let count: Int
        let entries: [Entry]  // Copy of entries at iteration start
    }

    private var bucketSnapshot: BucketSnapshot?
}
```

### Phase 3: Collection Conformance
Implement proper Collection support:

1. **Stable count**: Cache the count when the tree is created/modified
2. **Index-based access**: Implement proper Index type that includes bucket position
3. **Lazy iteration**: Don't materialize all entries, iterate on-demand

### Phase 4: COW Semantics
Ensure copy-on-write works correctly with buckets:

1. **Unique check**: Before modifying a bucket, check if it's uniquely referenced
2. **Clone on write**: If shared, create a new bucket with the modifications
3. **Update parent**: Ensure parent nodes are updated when buckets are cloned

## Implementation Steps

### Step 1: Basic Bucket Structure
- [ ] Create NodeBucketLeaf.swift with stable storage
- [ ] Add capacity limit (32 entries)
- [ ] Implement basic insert/remove/find operations
- [ ] Add proper memory management with ManagedBuffer

### Step 2: Integration Points
- [ ] Update NodeType enum to include .bucketLeaf
- [ ] Modify allocateLeaf to create bucket leaves
- [ ] Update ARTree+insert to handle bucket insertion
- [ ] Update ARTree+delete to handle bucket deletion
- [ ] Update ARTree+get to search within buckets

### Step 3: Iterator Support
- [ ] Modify ARTree+Sequence to iterate through bucket entries
- [ ] Add bucket position tracking to iterator state
- [ ] Implement snapshot mechanism for stability
- [ ] Add tests for concurrent iteration

### Step 4: Collection Support
- [ ] Update ARTree+Collection with bucket-aware index
- [ ] Implement proper count caching
- [ ] Add BidirectionalCollection support for buckets
- [ ] Ensure map()/filter()/etc. work correctly

### Step 5: Optimization
- [ ] Use SIMD for bucket searches
- [ ] Implement bucket splitting when full
- [ ] Add bucket merging for underutilized buckets
- [ ] Profile and optimize hot paths

## Testing Strategy

### Unit Tests
1. **BucketLeafTests.swift**:
   - Test insertion up to capacity
   - Test removal and compaction
   - Test key searching with SIMD
   - Test COW behavior

2. **BucketIterationTests.swift**:
   - Test iteration stability
   - Test concurrent iterations
   - Test modification during iteration
   - Test Collection.map() specifically

### Integration Tests
1. **Test with existing test suite**: All existing tests must pass
2. **Memory benchmarks**: Verify 67% memory reduction
3. **Performance benchmarks**: Ensure no regression
4. **Stress tests**: Large trees with many buckets

### Specific Test Cases
```swift
// Test that triggered the original failure
func testMapWithBuckets() {
    var tree = ARTree()
    for i in 0..<10 {
        tree.insert(key: [UInt8(i)], value: i)
    }

    // This should not crash
    let mapped = tree.map { $0 }
    #expect(mapped.count == 10)
}

// Test iteration stability
func testIterationStability() {
    var tree = ARTree()
    for i in 0..<100 {
        tree.insert(key: [UInt8(i)], value: i)
    }

    let count1 = tree.count
    let count2 = tree.reduce(0) { acc, _ in acc + 1 }
    let count3 = tree.map { $0 }.count

    #expect(count1 == count2)
    #expect(count2 == count3)
}
```

## Expected Outcomes

### Memory Improvements
- **Current**: ~62 bytes/entry
- **Target**: ~20.5 bytes/entry
- **Reduction**: 67%

### Performance Impact
- **Insert**: Slightly faster due to better cache locality
- **Search**: Potentially faster with SIMD bucket search
- **Iteration**: Similar performance with proper implementation
- **Delete**: May be slightly slower due to bucket compaction

## Risk Mitigation

### Risk 1: Collection Conformance
**Mitigation**: Extensive testing of all Collection methods, especially map(), with bucket leaves

### Risk 2: COW Complexity
**Mitigation**: Clear ownership model, comprehensive COW tests

### Risk 3: Performance Regression
**Mitigation**: Continuous benchmarking, SIMD optimizations

### Risk 4: Memory Fragmentation
**Mitigation**: Fixed-size buckets, periodic compaction

## Alternative Approaches

### Option 1: Adaptive Node Sizes
Instead of fixed 32-entry buckets, use adaptive sizes (4, 8, 16, 32) based on usage patterns.

### Option 2: B+ Tree Leaves
Use B+ tree style leaves with next/prev pointers for faster iteration.

### Option 3: Memory Pool
Allocate buckets from a memory pool to reduce allocation overhead.

## References
- Original ART paper: https://db.in.tum.de/~leis/papers/ART.pdf
- Swift Collections: https://github.com/apple/swift-collections
- Previous implementation attempt: See git history before commit 2394db2

## Next Session Checklist
When resuming this work:
1. Review this plan and current state
2. Start with Step 1: Basic Bucket Structure
3. Write comprehensive tests BEFORE implementation
4. Use `swift test --filter BucketLeafTests` for quick iteration
5. Monitor memory usage with benchmarks after each step
6. Keep Collection conformance as the top priority

## Commands for Testing
```bash
# Run specific tests during development
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter BucketLeafTests

# Check memory usage
swift run -c release Benchmarks run memory --filter "RadixTree" results.json

# Run all tests to ensure no regression
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test

# Run benchmarks
swift run -c release Benchmarks run all --cycles 1 benchmark-results.json
```