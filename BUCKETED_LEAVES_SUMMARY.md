# Bucketed Leaves: Quick Reference & Architecture Summary

## Current State

**Single-Leaf Architecture:**
- 1 key-value pair per leaf node
- Leaves are terminal nodes (no children)
- Memory: `[keyLength: UInt32][keyBytes...][value: Value]`
- Storage: `NodeStorage<NodeLeaf<Spec>>` (ManagedBuffer wrapper)
- Insertion creates leaf + Node4 parent when key collides

**Problem:** High tree depth, many small allocations, poor cache locality

## Proposed Solution

**Bucketed Leaves (32 entries/leaf):**
- 1-32 key-value pairs per leaf
- Maintains sorted order within bucket
- Same COW semantics as current leaves
- Reduces tree depth ~5x
- Improves cache locality

---

## Key Architectural Decisions

### 1. Memory Layout (Option A: Linear Array)

```
Header (16 bytes):
  count: UInt16           // 0..32
  partialLength: UInt8    // optional prefix compression
  partialBytes[8]: UInt8  // for deep buckets

Key Lengths (64 bytes):
  keyLength[0..31]: UInt16[32]

Entry Data (variable):
  [key0][val0][key1][val1]...
```

**Why Option A (vs binary search)?**
- Linear search O(32) negligible vs tree ops
- Simpler layout, less memory waste
- No extra indirection for key access

### 2. Bucket Operations

| Op | Complexity | Notes |
|----|-----------|-------|
| Lookup | O(32) | Linear scan, compare byte-wise |
| Insert | O(32) | Shift entries right, copy key+value |
| Delete | O(32) | Shift entries left, return value |
| Split | O(33 log 33) | Collect 33, sort, create 2 buckets of 16-17 |

**Split strategy:** When 33rd key arrives:
1. Collect all 33 entries (32 in bucket + 1 new)
2. Sort by full key (lexicographic)
3. Split at midpoint: left=entries 0-15, right=entries 16-32
4. Extract splitKeyByte from entry 16 at current depth
5. Create Node4 parent with both buckets as children

### 3. COW Integration

**Uniqueness path invariant preserved:**
- Insert: `_findInsertNode` clones shared buckets before mutation
- Delete: `updateChild` uses `withSelfOrClone` before remove
- Path compression: Works same as before (merge single-child node's prefix)

**Deallocation safety:**
```swift
final class Buffer: RawNodeBuffer {
  deinit {
    let bucket = NodeBucketLeaf(buffer: self)
    for i in 0..<bucket.count {
      bucket.valuePointer(at: i).deinitialize(count: 1)
    }
  }
}
```

### 4. Iteration

**Challenge:** Iterator expects children (recursion), but buckets are terminal.

**Solution:** Special bucket state in iterator:
```swift
struct _Iterator {
  var path: [_IterFrame]           // internal nodes
  var currentBucket: NodeBucketLeaf?
  var bucketIndex: Int
}
```

When reaching bucket:
1. Set currentBucket, reset bucketIndex to 0
2. Yield entries 0..count-1 before advancing parent cursor
3. Clear currentBucket, continue tree walk

---

## Implementation Phases

### Phase 1: Core Structure (1-2 days)
**Files:**
- `NodeBucketLeaf.swift` (500 lines) — header, accessors, find/insert/remove/split
- Tests (300 lines) — unit tests for all ops
- Modify: `NodeType.swift`, `RawNode.swift` (dispatch)

**Deliverable:** Standalone bucket operations tested

### Phase 2: Insertion (2-3 days)
**Modify:** `ARTree+insert.swift`
- Add `.replaceBucket`, `.splitBucketLeaf` to InsertAction
- Implement `allocateBucketLeaf`
- Dispatch bucket insert in `_findInsertNode`
- Split bucket logic (create Node4 parent)

**Tests:** Insert, replace, fill-to-split scenarios

### Phase 3: Deletion (2-3 days)
**Modify:** `ARTree+delete.swift`
- Dispatch `.bucketLeaf` in `_delete`
- Implement COW-safe bucket remove
- Handle empty bucket (propagate nil to parent)

**Tests:** Delete, empty bucket, path compression

### Phase 4: Iteration (1-2 days)
**Modify:** `ARTree+Sequence.swift`
- Add bucket state to iterator
- Dispatch _startIndex, _endIndex for buckets
- Implement nextLeaf for bucket entries
- Ensure sorted order

**Tests:** Iteration order, completeness

---

## Critical Implementation Details

### Entry Offset Calculation

```swift
func entryOffset(upTo index: Int) -> Int {
  var offset = 0
  for i in 0..<index {
    offset += Int(keyLengths[i]) + MemoryLayout<Value>.stride
  }
  return offset
}
```

**Why cumulative?** Variable-length keys mean can't use fixed stride; must sum all prior keys.

### Insert Algorithm (shifting)

```swift
// Shift key lengths array
for i in (index..<count).reversed() {
  keyLengths[i+1] = keyLengths[i]
}

// Shift entry data
let fromOffset = entryOffset(upTo: index)
let toOffset = fromOffset + newEntrySize
let moveSize = entryOffset(upTo: count) - fromOffset
memmove(entryData.advanced(by: toOffset), 
        entryData.advanced(by: fromOffset), 
        moveSize)
```

**Key:** Memmove handles overlapping copy correctly (shifts right-to-left internally).

### Clone Implementation

```swift
func clone() -> NodeStorage<Self> {
  let cloned = Self.allocateEmpty()
  cloned.read { newBucket in
    for i in 0..<self.count {
      let (key, value) = self.withEntry(at: i) { k, v in (k, v.pointee) }
      _ = newBucket.insert(at: i, keyBytes: key.withUnsafeBytes { $0 }, value: value)
    }
  }
  return cloned.storage
}
```

Copies all entries into fresh bucket (preserves sorted order, allocates new buffer).

---

## Integration Points (Dispatch Changes)

### NodeType enum (1 line)
```swift
enum NodeType {
  case leaf
  case bucketLeaf       // NEW
  case node4
  case node16
  case node48
  case node256
}
```

### RawNode dispatch (5 lines per method)
```swift
// In clone(), toARTNode()
case .bucketLeaf:
  return NodeStorage<NodeBucketLeaf<Spec>>(raw: buf).clone().rawNode
  
// New method
func toBucketLeaf<Spec>() -> NodeBucketLeaf<Spec> { ... }
```

### ARTree+insert InsertAction enum (2 cases)
```swift
case replaceBucket(NodeBucketLeaf<Spec>)      // NEW
case splitBucketLeaf(NodeBucketLeaf<Spec>, depth: Int)  // NEW
```

### ARTree+insert _findInsertNode (bucket logic)
- When reaching .bucketLeaf: call bucket.find(keyBytes)
- If found: return .replaceBucket
- If not found & bucket not full: return .insertIntoBucket (new action)
- If not found & bucket full: return .splitBucketLeaf

### ARTree+delete _delete (bucket case)
```swift
case .bucketLeaf:
  let bucket: NodeBucketLeaf = child!.toBucketLeaf()
  let (index, found) = bucket.find(keyBytes: key)
  guard found else { return .noop }
  
  if !isUniquePath {
    let clone = bucket.clone()
    child = clone.rawNode
    // remove from clone
  } else {
    // remove from bucket in-place
  }
```

### ARTree+Sequence Iterator (bucket state)
```swift
struct _Iterator {
  var path: [_IterFrame]
  var currentBucket: NodeBucketLeaf<Spec>?  // NEW
  var bucketIndex: Int = 0                  // NEW
}
```

In nextLeaf():
- If currentBucket is set, yield entries until exhausted
- When encountering .bucketLeaf child, set currentBucket and recursively call nextLeaf()

---

## Testing Strategy

### Unit Tests (NodeBucketLeafTests)
- Insert maintains sorted order
- Insert at various positions (start, middle, end)
- Fill to capacity (32 entries)
- Delete maintains order and count
- Find with exact match and binary search position
- Bucket split produces exactly 33 entries across left+right
- Cloning produces independent bucket

### Integration Tests
- Tree with cascading bucket splits
- COW: shallow copy, mutate one, other unchanged
- Delete from bucket, watch parent path compression
- Large tree (1000+ keys) with mixed ops
- Iteration order correctness (keys sorted)

### Simulation Tests (extend existing)
- Bucketed leaves with random ops
- Verify structural invariants
- Check COW correctness (multiple tree copies)
- LifetimeTracked values (no leaks on split/delete)

---

## Performance Model

### Space Efficiency
| Scenario | Single-Leaf | Bucketed | Reduction |
|----------|-------------|----------|-----------|
| 1000 short keys | 32KB tree | 18KB tree | 44% |
| 10K keys, 8-byte keys | 150KB tree | 90KB tree | 40% |

**Factors:**
- Fewer internal nodes (~5x shallower tree)
- Fewer allocations
- Denser key storage (packed in entry data)

### Time Complexity
- Insert: O(log₂₅₆ n) + O(32) ≈ O(log n) — same asymptotic
- Delete: O(log₂₅₆ n) + O(32) — same asymptotic
- Iterate: O(n) — unchanged
- Split: O(33 log 33) ≈ O(165) per split — rare, high tree load

---

## Risk Mitigation

| Risk | Mitigation |
|------|-----------|
| Bucket split data loss | Unit test verifies left.count + right.count == 33 |
| Memory corruption (shift) | AddressSanitizer, varied key sizes in tests |
| Value deinit leak | Explicit deinit in Buffer deinit, LifetimeTracked tests |
| COW violation (shared mutation) | Const.testCheckUnique flag, COW copy tests |
| Iteration order wrong | Sorted order verification in iterator tests |
| Path compression fails | Integration tests with single-child nodes |

---

## Files to Create/Modify

### Create
- `Sources/ARTreeModule/ARTree/NodeBucketLeaf.swift` (500 lines)
- `Tests/ARTreeModuleTests/NodeBucketLeafTests.swift` (300 lines)

### Modify
- `Sources/ARTreeModule/ARTree/NodeType.swift` (+1 line)
- `Sources/ARTreeModule/ARTree/RawNode.swift` (+10 lines)
- `Sources/ARTreeModule/ARTree/ARTree+insert.swift` (+50 lines)
- `Sources/ARTreeModule/ARTree/ARTree+delete.swift` (+30 lines)
- `Sources/ARTreeModule/ARTree/ARTree+Sequence.swift` (+40 lines)

**Total:** ~930 new lines, ~130 modified lines

---

## Success Criteria

1. All unit tests pass (NodeBucketLeafTests)
2. Integration tests verify COW semantics
3. Simulation suite runs without errors
4. Iteration yields sorted, unique keys
5. Memory sanitizers pass
6. No regressions in existing tree tests (with single-leaf legacy support)
7. Benchmarks show 30-40% space reduction
8. Performance neutral (same O(log n) complexity)

