# Bucketed Leaves: Architecture & Diagrams

## System Overview

### Current ARTree Architecture (Single Leaf)

```
                         ┌──────────┐
                         │   Root   │ RawNode?
                         └────┬─────┘
                              │
                    ┌─────────┴──────────┐
                    ▼                    ▼
              ┌──────────┐         ┌──────────┐
              │ Node4    │         │ Node4    │
              │ (4 slots)│         │ (4 slots)│
              └─────┬────┘         └────┬─────┘
                    │                   │
        ┌───────────┼───────────┐       │
        ▼           ▼           ▼       ▼
     [Leaf]      [Leaf]      [Leaf]  [Leaf]
     ("foo":1)   ("bar":2)   ("baz":3)("qux":4)

Each leaf: 1 key-value pair
Tree depth: O(log 256 n) [256-way fan-out from Node256]
Problem: Many small allocations, high depth
```

### Proposed Bucketed Architecture

```
                         ┌──────────────┐
                         │   Root       │ RawNode?
                         └──────┬───────┘
                                │
                    ┌───────────┴───────────┐
                    ▼                       ▼
              ┌──────────┐            ┌──────────┐
              │ Node4    │            │ Node4    │
              │ (4 slots)│            │ (4 slots)│
              └─────┬────┘            └────┬─────┘
                    │                      │
        ┌───────────┼───────────┐          │
        ▼           ▼           ▼          ▼
    [Bucket]   [Bucket]   [Bucket]   [Bucket]
     {0..5}     {6..11}    {12..17}   {18..23}
     entries    entries    entries    entries

Each bucket: 1-32 key-value pairs in sorted order
Tree depth: O(log 256 (n/32)) ≈ O(log n / 5) [5x shallower]
Benefit: Fewer allocations, better cache locality
```

---

## Memory Layout Comparison

### Single Leaf Node

```
ManagedBuffer Header:
┌────────────────┐
│ NodeType: leaf │  (enum discriminant)
└────────────────┘

ManagedBuffer Body:
┌───────────────────────────────────────────┐
│ keyLength: UInt32  (4 bytes)              │
├───────────────────────────────────────────┤
│ keyBytes: [UInt8]  (variable, keyLength)  │
├───────────────────────────────────────────┤
│ value: Value       (sizeof(Value) bytes)  │
└───────────────────────────────────────────┘

Memory cost per entry:
  Base: 4 (keyLength header) + keyLength + sizeof(Value)
  
Example (10-byte key, 8-byte value):
  4 + 10 + 8 = 22 bytes + ManagedBuffer overhead (~40 bytes) = ~62 bytes/entry
```

### Bucketed Leaf Node

```
ManagedBuffer Header:
┌────────────────────┐
│ NodeType: bucketLeaf  (enum discriminant)
└────────────────────┘

ManagedBuffer Body:
┌────────────────────────────────────────────────────────┐
│ NodeBucketLeafHeader (16 bytes)                        │
│  ├─ count: UInt16                                      │
│  ├─ partialLength: UInt8                               │
│  └─ partialBytes[8]: [UInt8]                           │
├────────────────────────────────────────────────────────┤
│ keyLength[32]: [UInt16]  (64 bytes, fixed)             │
├────────────────────────────────────────────────────────┤
│ Entry Data (variable)                                  │
│  [key0][val0][key1][val1]...[key31][val31]            │
└────────────────────────────────────────────────────────┘

Memory cost per bucket:
  Base: 16 + 64 = 80 bytes
  Entries: 32 * (avg_keyLength + sizeof(Value))
  
Example (32 entries, 10-byte keys, 8-byte values):
  80 + 32*(10+8) = 80 + 576 = 656 bytes for 32 entries
  ≈ 20.5 bytes/entry (vs 62 bytes/entry single-leaf)
  Savings: ~67% per entry
```

---

## Key Data Structure Details

### BucketLeafHeader

```swift
@usableFromInline
struct NodeBucketLeafHeader {
  var count: UInt16          // Number of entries in bucket [0, 32]
  var partialLength: UInt8   // Prefix compression (optional)
  var partialBytes: PartialBytes  // 8 bytes for deep prefixes
  // Total: 16 bytes (with padding)
}
```

**Why partialLength in leaf?** Enables future optimization for very deep buckets:
- When all 32 entries share 9+ byte prefix, compress it here
- Trade off: slower to add entries (must prepend prefix), faster to compare keys
- Currently: unused (set to 0)

### Entry Storage

```
┌─────────────────────────────────────────────┐
│ keyLengths[0..31]: UInt16[32]              │  64 bytes
├─────────────────────────────────────────────┤
│ Packed Entry Data:                          │
│ ┌──────────────────────────────────────┐   │
│ │ Entry 0:                             │   │
│ │  [key0_bytes: count[0]][val0]        │   │
│ ├──────────────────────────────────────┤   │
│ │ Entry 1:                             │   │
│ │  [key1_bytes: count[1]][val1]        │   │
│ ├──────────────────────────────────────┤   │
│ │ ...                                  │   │
│ ├──────────────────────────────────────┤   │
│ │ Entry 31 (if count == 32):           │   │
│ │  [key31_bytes: count[31]][val31]     │   │
│ └──────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
```

**Layout reason:** Split keyLength array from entry data because:
1. Fast lookup: scan keyLength[0..count-1] to find entry without scanning all data
2. Cache efficiency: short array fits in L1 cache
3. Offset calculation: `entryOffset(upTo: i)` walks keyLength array only

---

## Operation Workflows

### Insert Operation (Within Bucket)

```
Input: keyBytes: UnsafeRawBufferPointer, value: Value
Output: Bool (true if inserted, false if bucket full)

1. Check bucket full
   if count == 32 { return false }

2. Binary search for sorted position
   (index, found) = find(keyBytes)
   
3a. If found: update value at index
3b. If not found and index < count:
    - Shift keyLengths[index..count-1] right by 1
    - Shift entry data from offset(index) to end right by newEntrySize
    - Write new keyLength[index] and entry data at offset(index)
    - Increment count
    
4. Return true
```

### Delete Operation (Within Bucket)

```
Input: index: Int
Output: Value?

1. Bounds check: if index >= count { return nil }

2. Extract value at index

3. Shift entries left:
   - Shift keyLengths[index+1..count-1] left by 1
   - Shift entry data from offset(index+1) to end left by entrySize(index)
   - Decrement count

4. Return extracted value
```

### Bucket Split (When 33rd Entry Arrives)

```
Input: full: NodeBucketLeaf (32 entries), newKey, newValue, depth

Output: (left: NodeBucketLeaf, right: NodeBucketLeaf, splitKeyByte: UInt8)

1. Collect all 33 entries
   allEntries = [ full.entries[0..31], (newKey, newValue) ]

2. Sort by full key (lexicographic byte comparison)
   allEntries.sort()

3. Find split point
   splitEntry = allEntries[16]  // midpoint
   splitKeyByte = splitEntry.key[depth]

4. Create left bucket
   left = allocateEmpty()
   for i in 0..<16:
     left.insert(at: i, allEntries[i])

5. Create right bucket
   right = allocateEmpty()
   for i in 0..<17:
     right.insert(at: i, allEntries[16+i])

6. Return (left, right, splitKeyByte)

7. Parent creates Node4, adds left and right as children
```

### Iteration (Tree Walk)

```
State:
  path: [_IterFrame]            // Stack of (internal_node, child_index)
  currentBucket: NodeBucketLeaf?  // Currently iterating bucket
  bucketIndex: Int               // Index within bucket

nextLeaf():
  1. If currentBucket is set:
     - Return entry at bucketIndex
     - Increment bucketIndex
     - If bucketIndex >= currentBucket.count:
       - Clear currentBucket
     - Return result
   
  2. While path is not empty:
     - Get top node and its child index
     - If child index >= endIndex:
       - Pop from path
       - Continue
     
     - Get child at child index
     - If child is leaf:
       - Return as single-entry pseudo-leaf
       - Advance parent's index
     
     - If child is bucketLeaf:
       - Set currentBucket
       - Reset bucketIndex to 0
       - Recursively call nextLeaf() to yield first entry
     
     - If child is internal node:
       - Push new frame for child
       - Continue

  3. Return nil (tree exhausted)
```

---

## COW (Copy-On-Write) Interaction

### Insert with COW

```
_findInsertNode(key) walk:
  
  current = root
  isUnique = isKnownUniquelyReferenced(&root.buf)
  
  while current is not leaf and depth < key.count:
    
    if !isUnique:
      // Shared node: must clone before mutation
      cloned = current.clone()
      ref.pointee = cloned
      current = cloned
      isUnique = true
    
    if current is internalNode:
      // Descend into child
      (step, childUnique) = _insertStep(current, key, &depth, &ref)
      current = step.child
      isUnique = childUnique

  // Reached leaf (or bucketLeaf)
  if !isUnique:
    current = current.clone()  // Clone before mutation

  // Now we can safely mutate current (unique on path)
  switch action:
    case .insertIntoBucket:
      let (index, found) = bucket.find(key)
      if !found and bucket.count < 32:
        bucket.insert(at: index, key, value)  // In-place, safe
      else if bucket.count == 32:
        // Split bucket (creates new buckets, updates parent)
        
Key invariant:
  "At each node, if not unique, clone before touching"
```

### Delete with COW

```
_delete(child, key, depth, isUniquePath):
  
  if child is leaf/bucketLeaf:
    // Find and remove entry
    if isUniquePath:
      // Mutate in-place
      bucket.remove(at: foundIndex)
    else:
      // Must clone
      cloned = bucket.clone()
      cloned.remove(at: foundIndex)
      child = cloned

Deinit Safety:
  final class Buffer: RawNodeBuffer {
    deinit {
      let bucket = NodeBucketLeaf(buffer: self)
      for i in 0..<bucket.count {
        // Explicitly deinitialize values (calls Value's deinit)
        bucket.valuePointer(at: i).deinitialize(count: 1)
      }
    }
  }
```

---

## Entry Offset Calculation

### Problem

Variable-length keys means can't compute offset to entry i with fixed formula. Must know lengths of entries 0..i-1.

### Solution

```swift
func entryOffset(upTo index: Int) -> Int {
  var offset = 0
  for i in 0..<index {
    // key length + value size
    offset += Int(keyLengths[i]) + MemoryLayout<Value>.stride
  }
  return offset
}
```

**Complexity:** O(index), worst case O(32)

**Why acceptable:**
- Called during insert/delete (at most once per op)
- 32 iterations negligible vs tree traverse O(log n)
- Could optimize with prefix sums if 32 entries becomes bottleneck

---

## Type System Integration

### ARTNode Protocol

```swift
protocol ARTNode<Spec> {
  associatedtype Spec: ARTreeSpec
  associatedtype Buffer: RawNodeBuffer
  
  typealias Storage = UnmanagedNodeStorage<Self>
  
  static var type: NodeType { get }
  var storage: Storage { get }
  func clone() -> NodeStorage<Self>
}
```

**Conformances:**
- `NodeLeaf<Spec>: ARTNode`
- `NodeBucketLeaf<Spec>: ARTNode` (NEW)
- `Node4<Spec>: InternalNode` (extends ARTNode)
- `Node16<Spec>: InternalNode`
- etc.

### Dispatch via RawNode

```swift
struct RawNode {
  var buf: RawNodeBuffer
  
  var type: NodeType { buf.header }
  
  func clone<Spec>(spec: Spec.Type) -> RawNode {
    switch type {
    case .leaf:
      return NodeStorage<NodeLeaf<Spec>>(raw: buf).clone().rawNode
    case .bucketLeaf:  // NEW
      return NodeStorage<NodeBucketLeaf<Spec>>(raw: buf).clone().rawNode
    case .node4:
      return NodeStorage<Node4<Spec>>(raw: buf).clone().rawNode
    // ...
    }
  }
  
  func toARTNode<Spec>() -> any ARTNode<Spec> {
    switch type {
    case .leaf:
      return NodeLeaf<Spec>(buffer: buf)
    case .bucketLeaf:  // NEW
      return NodeBucketLeaf<Spec>(buffer: buf)
    case .node4:
      return Node4<Spec>(buffer: buf)
    // ...
    }
  }
}
```

**Key:** Single `RawNode` type, dispatch at runtime via type tag

---

## Test Architecture

### Unit Tests: NodeBucketLeaf Isolation

```
NodeBucketLeafTests:
  - testInsertMaintainsSortedOrder
  - testInsertShiftsEntriesCorrectly
  - testFillToCapacityAndFail
  - testDeleteMaintainsOrder
  - testDeleteAllEntries
  - testSplitProduces33Entries
  - testCloneIsIndependent
  - testDestructorCalled
```

### Integration Tests: Tree + Buckets

```
BucketTreeIntegrationTests:
  - testInsertCausesBucketSplit
  - testCOWShallowCopyIndependent
  - testIterationYieldsSortedOrder
  - testDeleteFromBucketAndCompress
  - testLargeTreeWithMixedOps
```

### Simulation: Existing + Buckets

```
Extend ARTreeSoakTests with:
  USE_BUCKETED_LEAVES=true
  Verify:
    - No structural invariants violated
    - All keys present and ordered
    - No memory leaks (LifetimeTracked)
    - COW semantics preserved
```

---

## Performance Metrics to Measure

### Space Usage
- Single tree, 1000 keys: measure heap size
- Multiple copies (COW): shallow copies shouldn't increase heap
- Fragmentation: check allocation patterns

### Time (Micro-benchmarks)
- Insert 1000 keys sequentially
- Iterate all 1000 keys
- Delete 500 keys
- Shallow copy + 100 mutations

### Expected Results
- Space: 30-40% reduction
- Time: ±5% (constant factors dominate, asymptotic same)
- Tree depth: ~5x shallower (measured via instrumentation)

---

## Rollout Plan

### Phase 1: Feature Gate (All Tests)
```swift
#if USE_BUCKETED_LEAVES
  static func allocateLeaf(...) -> NodeStorage<NodeBucketLeaf<Spec>> { ... }
#else
  static func allocateLeaf(...) -> NodeStorage<NodeLeaf<Spec>> { ... }
#endif
```

Default: off (use single-leaf for compatibility)

### Phase 2: Gradual Enable
- Enable for new tests
- Run full simulation suite
- Monitor for any failures

### Phase 3: Default On
- Flip default to bucketed
- Keep single-leaf support (deprecated)
- Update docs

### Phase 4: Cleanup
- Remove single-leaf support
- Update examples, benchmarks

---

## Edge Cases & Invariants

### Invariant: Sorted Order Maintained

**Insert:** Must scan to find correct position before shifting
**Delete:** Order preserved by shifting
**Split:** Sort all 33, then split at midpoint

**Test:** Iterate tree after each op, verify keys strictly increasing

### Invariant: Count Never Exceeds 32

**Insert:** Check `count == 32` before inserting, return false if full
**Delete:** Decrement count
**Split:** Create new buckets, never leave full bucket

**Test:** Assert `count <= 32` after every mutation

### Invariant: All Values Destructed

**Insert:** New value initialized
**Delete:** Value extracted before removing
**Split:** Each value moved to new bucket (not copied, moved)
**Clone:** Each value copied to new bucket

**Test:** Use LifetimeTracked, check no leaks on split/delete

### Invariant: COW Path Unique

**Insert:** Check uniqueness before mutating
**Delete:** Clone if not unique before removing

**Test:** Shallow copy tree, mutate both, verify independence

---

## Debugging Aids

### Assertions

```swift
// In find()
assert(count <= maxEntries, "bucket overfilled")

// In insert()
assert(index <= count, "invalid insert position")
assert(keyLengths[i] < 10000, "key length sanity check")

// In entryOffset()
assert(index <= count, "offset calculation out of bounds")
```

### Logging (Optional)

```swift
if Const.testPrintAddr {
  print("Bucket \(ObjectIdentifier(self)): insert \(keyBytes.count)-byte key at \(index)")
}
```

---

## References

- Current implementation: `Sources/ARTreeModule/ARTree/`
- Tests: `Tests/ARTreeModuleTests/`
- Simulation: `Tests/ARTreeModuleTests/Simulation/`
- COW semantics: `ARTree+insert.swift` lines 99-115
- Iteration: `ARTree+Sequence.swift` lines 94-133

