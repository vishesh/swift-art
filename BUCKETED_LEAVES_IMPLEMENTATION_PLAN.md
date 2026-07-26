# Implementation Plan: Bucketed Leaves for ARTree

## Executive Summary

Transform ARTree from single-key-value-per-leaf to bucketed leaves (32 pairs/leaf) while maintaining COW semantics and sorted order. This reduces tree depth, improves cache locality, and enables efficient bulk operations.

---

## 1. Current Architecture Analysis

### 1.1 NodeLeaf Structure
**File:** `Sources/ARTreeModule/ARTree/NodeLeaf.swift`

Current design:
- Single `Key` (variably-sized, null-terminated bytes) and `Value` per leaf
- Memory layout: `[keyLength: UInt32][keyBytes...][value: Value]`
- Fixed header size: 4 bytes (keyLength)
- Variable key size: stored inline
- Value stored immediately after key

Key characteristics:
- **Allocation:** Dynamic size computed as `4 + keyLength + sizeof(Value)`
- **Storage:** Via `NodeStorage<NodeLeaf<Spec>>` (ManagedBuffer wrapper)
- **Access:** Unsafe pointer arithmetic with proper bounds
- **Clone:** Copies both key and value to new allocation

### 1.2 NodeType Enum
**File:** `Sources/ARTreeModule/ARTree/NodeType.swift`

Current types:
```swift
enum NodeType {
  case leaf
  case node4
  case node16
  case node48
  case node256
}
```

This is a discriminant stored in the ManagedBuffer header. Internal nodes scale by branching factor; leaves don't scale.

### 1.3 Node Storage & Memory Layout
**File:** `Sources/ARTreeModule/ARTree/NodeStorage.swift` + `RawNode.swift`

Storage stack:
1. `RawNodeBuffer` = `ManagedBuffer<NodeType, UInt8>` (header is NodeType enum, body is typed as bytes)
2. `RawNode` = thin wrapper around `RawNodeBuffer` with type dispatch
3. `NodeStorage<N: ARTNode>` = downcasted reference to specific node type
4. Concrete node type (e.g., `NodeLeaf`, `Node4`) = value type wrapping storage

Memory model:
- Header: `NodeType` (implicit, stored in ManagedBuffer.header)
- Body: contiguous `UInt8` array accessed via unsafe pointers
- Type safety through downcasting and layout coordination

### 1.4 Internal Nodes Pattern
**File:** `Sources/ARTreeModule/ARTree/InternalNode.swift`, `Node4.swift`, etc.

Structure for N4:
```
[InternalNodeHeader: count, partialLength, partialBytes[8]]
[keys: KeyPart[4]]
[children: RawNode?[4]]
```

Allocation:
```swift
static var size: Int {
  MemoryLayout<InternalNodeHeader>.stride + 
  numKeys * (sizeof(KeyPart) + sizeof(RawNode?))
}
```

Key patterns:
- Fixed-size storage allocated upfront
- Sparse occupancy (not all slots used, tracked by `count`)
- Layout: header, then variable-length body
- No dynamic resizing within a node type

---

## 2. Insertion, Deletion & Iteration Flow

### 2.1 Insertion Path
**File:** `Sources/ARTreeModule/ARTree/ARTree+insert.swift`

High-level flow:
1. `insert(key, value)` calls `_findInsertNode(keyBytes)` 
2. Returns `InsertAction` enum:
   - `.replace(leaf)` — key exists, update in-place
   - `.splitLeaf(leaf, depth)` — key collides, create Node4 parent
   - `.splitNode(rawNode, depth, prefixDiff)` — internal node prefix mismatch
   - `.insertInto(rawNode, depth)` — descend and add child to internal node

3. On `.replace`: mutates the leaf's value
4. On `.splitLeaf`: creates new Node4, adds both leaves as children (compressing common prefix)
5. COW handled in `_findInsertNode` loop:
   - Check `isKnownUniquelyReferenced(&_root!.buf)`
   - If shared (not unique), clone before mutation

Key insight: **All mutation happens on the unique path only.** The tree is walked from root, and at each internal node, if it's shared, it's cloned before mutation.

### 2.2 Deletion Path
**File:** `Sources/ARTreeModule/ARTree/ARTree+delete.swift`

Flow:
1. `delete(key)` recursively descends via `_delete(child, key, depth, isUniquePath)`
2. Leaf check: if found and key matches, return `.replaceWith(nil)`
3. Internal nodes: dispatch to `updateChild(forKey:isUniquePath:body:)`
4. COW in `updateChild`:
   - Uses `withSelfOrClone(isUnique:body:)` to mutate only if unique
   - If child removal leaves one child (path compression): merge prefixes if ≤ 8 bytes

Key insight: **Deletion can trigger path compression** if a node is left with a single child. This happens in-place on the unique path.

### 2.3 Iteration
**File:** `Sources/ARTreeModule/ARTree/ARTree+Sequence.swift`

Iterator design:
- Traversal stack: `[_IterFrame]` where each frame = `(node: RawNode, index: Int)`
- Depth-first left-to-right walk
- Special case: if root is a leaf, yield it once
- Per node: dispatch via `_startIndex`, `_endIndex`, `_indexAfter`, `_childAt` (concrete per type)
- Returns `(key, value)` tuples

Important: **Iteration calls `nextLeaf()` internally, which can be overridden to yield just leaves without constructing full `(Key, Value)` tuples.**

---

## 3. Design Constraints

### 3.1 COW (Copy-On-Write) Requirements
1. **Uniqueness checks must happen before binding child references** (see ARTree+insert line 99-100):
   - "it adds a second ref to the root buffer, which would otherwise make a unique root look shared"
2. **Cloning is surgical**: only cloned nodes are mutated; siblings remain shared
3. **Path compression requires child cloning** because the modified child may have been originally shared with other trees
4. **Deinit safety**: `NodeLeaf.Buffer` deinit explicitly calls `deinitialize` on the value to run destructors

### 3.2 Invariants
1. **Leaves are terminal**: internal nodes cannot point to partial keys; all prefixes must be complete
2. **Ordered traversal**: iteration must yield keys in sorted order (keys are big-endian-comparable bytes)
3. **Partial bytes**: internal nodes store up to 8 bytes of compressed prefix; longer shared prefixes trigger node creation
4. **No empty internal nodes**: nodes have at least 2 children (except Node4 temporarily during path compression)

### 3.3 Performance Constraints
1. **Allocation cost**: each insert creates leaf, then possibly Node4 parent → critical path
2. **Deallocation**: COW means multiple leaf clones exist; deinit must be reliable
3. **Uniqueness checks**: must not add spurious refs that kill uniqueness detection
4. **Type dispatch**: switch on `RawNode.type` specializes per node, avoiding v-table overhead

---

## 4. Bucketed Leaves Architecture

### 4.1 New Data Structure

**Two possible layouts:**

#### Option A: Flat array of (key, value) pairs + linear search
```
[BucketLeafHeader: count, isLeaf=true]
[entryLength[count]: UInt16[32]]   // stores keyLength for each entry
[entries[32]]                        // variable-length (key||value) data
```

Pros: Simple, minimal overhead, cache-friendly for small counts
Cons: Linear search O(32) but acceptable for small n

#### Option B: Binary search with key indices
```
[BucketLeafHeader: count, isLeaf=true]
[keyOffsets[32]: UInt16[32]]       // start offset of each entry
[entries...]                        // packed variable-length entries
```

Pros: Binary search O(log 32) ≈ 5 comparisons
Cons: Extra indirection, need to decode key at each offset

**Recommendation: Option A** — for 32 entries, linear search is negligible, and the simpler layout reduces memory waste and complexity.

### 4.2 Memory Layout (Option A)

```
┌─────────────────────────────────────────────┐
│ BucketLeafHeader (16 bytes)                 │
│  count: UInt16        (# of kv pairs)       │
│  partialLength: UInt8 (for prefix comp)     │
│  partialBytes[7]: [UInt8]                   │
├─────────────────────────────────────────────┤
│ Entry Count Array (64 bytes = 32 × UInt16)  │
│  keyLength[0], keyLength[1], ..., [31]      │
├─────────────────────────────────────────────┤
│ Packed Entry Data (variable)                │
│  [key0 bytes][val0][key1 bytes][val1]...    │
└─────────────────────────────────────────────┘

Total header: 16 + 64 = 80 bytes
Max entry data: 32 * (max_key_size + sizeof(Value))
```

**Why partialBytes in leaf?**
- Enables path compression when a bucket itself becomes too deep
- Optional optimization: usually only used during split

### 4.3 Key Operations on Buckets

#### 4.3.1 Lookup (within bucket)
```swift
func find(keyBytes: UnsafeRawBufferPointer) -> (index: Int, found: Bool)?
```
Linear scan through entries:
1. For each i in 0..<count:
   - Decode keyLength[i]
   - Compare keyBytes with stored key
   - Return (i, true) if match
2. Return (insertIndex, false) where insertIndex is sorted position

Time: O(count) = O(32) worst case

#### 4.3.2 Insert into bucket
```swift
mutating func insert(at index: Int, keyBytes: UnsafeRawBufferPointer, value: Value) -> Bool
```
Precondition: `index` is sorted position (from lookup), bucket not full

Steps:
1. If count == 32: return false (bucket full, parent must split)
2. Shift entries >= index one position right
3. Copy keyLength[index] and key||value into packed data
4. Increment count
5. Return true

#### 4.3.3 Delete from bucket
```swift
mutating func remove(at index: Int) -> Value?
```
Steps:
1. If index >= count: return nil
2. Extract value at index
3. Shift entries (index+1..count) one position left
4. Decrement count
5. Return value

#### 4.3.4 Split bucket
When a 33rd key arrives, split bucket into two:
```swift
static func split(full: NodeBucketLeaf, newKey: UnsafeRawBufferPointer, value: Value) 
  -> (left: NodeBucketLeaf, right: NodeBucketLeaf, splitKey: UInt8)
```

Algorithm:
1. Collect all 33 entries (32 in bucket + 1 new)
2. Sort by key
3. Determine splitKey = keyBytes[depth + partialLength] at midpoint (entry 16)
4. Create two leaves:
   - Left: entries 0..15 (keys < splitKey)
   - Right: entries 16..32 (keys >= splitKey)
5. Return (left, right, splitKey)

---

## 5. Implementation Phases

### Phase 1: Add NodeType variant + basic structure (Module 1)

**Files to create:**
- `Sources/ARTreeModule/ARTree/NodeBucketLeaf.swift`

**Files to modify:**
- `Sources/ARTreeModule/ARTree/NodeType.swift` — add `.bucketLeaf` case
- `Sources/ARTreeModule/ARTree/RawNode.swift` — add case handlers
- `Sources/ARTreeModule/ARTree/ARTree+insert.swift` — dispatch to bucket insert
- `Sources/ARTreeModule/ARTree/ARTree+delete.swift` — dispatch to bucket delete
- `Sources/ARTreeModule/ARTree/ARTree+Sequence.swift` — dispatch to bucket iteration

**Key definitions:**
```swift
enum NodeType {
  case leaf
  case bucketLeaf  // NEW
  case node4
  case node16
  case node48
  case node256
}

struct BucketLeafHeader {
  var count: UInt16 = 0
  var partialLength: UInt8 = 0
  var partialBytes: PartialBytes = PartialBytes(repeating: 0)
}

struct NodeBucketLeaf<Spec: ARTreeSpec> {
  var storage: Storage
  
  static var type: NodeType { .bucketLeaf }
  
  // Memory access helpers
  var header: BucketLeafHeader { ... }
  var keyLengths: UnsafeMutableBufferPointer<UInt16> { ... }
  var entryData: UnsafeMutableRawPointer { ... }
}
```

**Tests:**
- `Tests/ARTreeModuleTests/NodeBucketLeafTests.swift` — unit tests for insert/delete/lookup

---

### Phase 2: Insertion integration (Module 2)

**Modify `ARTree+insert.swift`:**

1. **Allocation:**
```swift
static func allocateBucketLeaf(keyBytes key: UnsafeRawBufferPointer, value: Value) 
  -> NodeStorage<NodeBucketLeaf<Spec>>
{
  // Allocate single-entry bucket
  let keyLength = key.count
  let size = sizeof(BucketLeafHeader) + 32 * sizeof(UInt16) + keyLength + sizeof(Value)
  let storage = NodeStorage<NodeBucketLeaf>.create(type: .bucketLeaf, size: size)
  storage.update { bucket in
    bucket.count = 1
    bucket.keyLengths[0] = UInt16(keyLength)
    // Copy key and value into entryData
  }
  return storage
}
```

2. **InsertAction variants:**
```swift
enum InsertAction {
  case replace(NodeLeaf<Spec>)
  case replaceBucket(NodeBucketLeaf<Spec>)      // NEW
  case splitLeaf(NodeLeaf<Spec>, depth: Int)
  case splitBucketLeaf(NodeBucketLeaf<Spec>, depth: Int)  // NEW
  // ...
}
```

3. **_findInsertNode logic for buckets:**
   - When reaching a `.bucketLeaf` node at depth < key.count:
     - Try bucket lookup → if found and depth+partialLength == key.count, return `.replaceBucket`
     - If found but depth < key.count, need to split bucket (all 32 entries share prefix, diverge later)
     - If not found and bucket not full, return `.insertIntoBucket`
     - If not found and bucket full, return `.splitBucketLeaf` → parent splits bucket into Node4 with two children

4. **Insertion cases in `insert(key:value)`:**
```swift
case .replaceBucket(let bucket):
  bucket.withValue(at: foundIndex) { $0.pointee = value }

case .splitBucketLeaf(let bucket, let depth):
  // Same logic as splitLeaf, but buckets can hold 32 collisions
  let newBucketLeaf = allocateBucketLeaf(keyBytes: key, value: value)
  // ... find longest prefix of all 32 bucket entries vs new key
  // ... create Node4 parent, add both buckets
```

**Tests:**
- Simple insert into bucket
- Replace value in bucket
- Bucket full → split into Node4
- Multiple inserts building up to split

---

### Phase 3: Deletion integration (Module 3)

**Modify `ARTree+delete.swift`:**

1. **Case dispatch:**
```swift
private mutating func _delete(
  child: inout RawNode?, 
  keyBytes key: UnsafeRawBufferPointer,
  depth: Int, 
  isUniquePath: Bool
) -> UpdateResult<RawNode?> {
  
  switch child?.type {
  case .leaf:
    // existing leaf logic
    
  case .bucketLeaf:
    let bucket: NodeBucketLeaf = child!.toBucketLeaf()
    if let index = bucket.find(keyBytes: key) {
      bucket.remove(at: index)
      if bucket.count == 0 {
        return .replaceWith(nil)
      }
      return .noop  // bucket modified in-place (if unique)
    }
    return .noop  // key not found
    
  case .node4, .node16, .node48, .node256:
    // existing internal node logic
  }
}
```

2. **Bucket-specific removals:**
   - If bucket becomes empty after deletion → parent removes bucket child
   - If bucket shrinks to 1 entry → optional: could decompose to single leaf? (conservative: keep as bucket)

**Tests:**
- Delete from bucket
- Delete all entries in bucket
- Delete one entry, parent path compression

---

### Phase 4: Iteration integration (Module 4)

**Modify `ARTree+Sequence.swift`:**

1. **Iterator dispatch for buckets:**
```swift
extension ARTreeImpl._Iterator {
  static func _startIndex(_ node: RawNode) -> Int {
    switch node.type {
    case .bucketLeaf:
      return 0  // bucket entries are 0..count-1
    case .node4, .node16, .node48, .node256:
      // existing logic
    case .leaf:
      return 0
    }
  }
  
  static func _childAt(_ node: RawNode, _ index: Int) -> RawNode? {
    switch node.type {
    case .bucketLeaf:
      return nil  // buckets don't have children; return the entry instead
    // But wait — iteration expects children, not entries in buckets...
    }
  }
}
```

**Key insight:** Buckets are terminal nodes (no children). Iteration must treat a bucket specially:
- Instead of recursing into children, yield each entry in the bucket
- This requires a new iterator state: "yield entries from bucket"

```swift
struct _Iterator {
  var path: [_IterFrame]  // internal nodes
  var currentBucket: NodeBucketLeaf<Spec>?
  var bucketIndex: Int = 0
}

mutating func nextLeaf() -> NodeLeaf<Spec>? {
  // If currently iterating bucket entries, yield next entry wrapped as pseudo-leaf
  if let bucket = currentBucket {
    let entry = bucket.entryAt(bucketIndex)
    bucketIndex += 1
    if bucketIndex >= bucket.count {
      currentBucket = nil
    }
    // Return synthetic leaf? Or return tuple (Key, Value) directly?
    // Option: create temporary NodeLeaf on stack? (no, can't allocate on heap)
    // Option: modify iterator to yield (Key, Value) directly from bucket entries
    return ... // challenge: we expect NodeLeaf
  }
  
  // Normal path: walk internal nodes
  while let top = path.last {
    // ... existing logic
    if child.type == .bucketLeaf {
      let bucket = child.toBucketLeaf()
      currentBucket = bucket
      bucketIndex = 0
      return nextLeaf()  // recursive call yields first bucket entry
    }
    // ...
  }
}
```

**Better approach:** Modify `nextLeaf()` to handle bucket entries inline:

```swift
mutating func nextLeaf() -> (key: Key, value: Value)? {
  // If iterating bucket, yield next entry
  if let bucket = currentBucket, bucketIndex < bucket.count {
    let (key, value) = bucket.entryAt(bucketIndex)
    bucketIndex += 1
    if bucketIndex >= bucket.count {
      currentBucket = nil
    }
    return (key, value)
  }
  
  while let top = path.last {
    if index >= _endIndex(node) {
      path.removeLast()
      if !path.isEmpty {
        path[count-1].index = _indexAfter(parent, path[count-1].index)
      }
      continue
    }
    
    let child = _childAt(node, index)!
    if child.type == .bucketLeaf {
      currentBucket = child.toBucketLeaf()
      bucketIndex = 0
      path[count-1].index = _indexAfter(node, index)
      return nextLeaf()  // yield first bucket entry
    } else if child.type == .leaf {
      path[count-1].index = _indexAfter(node, index)
      return child.toLeafNode().keyValue
    } else {
      path.append(...)
    }
  }
  return nil
}
```

**Tests:**
- Iterate over tree with buckets
- Verify order is correct (keys in sorted order)
- Verify all entries yielded

---

## 6. Detailed Implementation: NodeBucketLeaf

### 6.1 Header Definition

```swift
@usableFromInline
struct NodeBucketLeafHeader {
  var count: UInt16 = 0           // 0..32, number of stored entries
  var partialLength: UInt8 = 0    // optional prefix compression within bucket
  var partialBytes: PartialBytes = PartialBytes(repeating: 0)  // 8 bytes
  
  static var stride: Int { MemoryLayout<Self>.stride }  // ≈ 16 bytes
}

@usableFromInline
struct NodeBucketLeaf<Spec: ARTreeSpec> {
  var storage: Storage  // UnmanagedNodeStorage<NodeBucketLeaf>
  
  static var type: NodeType { .bucketLeaf }
  
  // Max entries per bucket
  static let maxEntries = 32
  
  // Fixed slot array for key lengths
  static let keysArraySize = maxEntries * MemoryLayout<UInt16>.stride  // 64 bytes
}
```

### 6.2 Memory Accessors

```swift
extension NodeBucketLeaf {
  var count: Int {
    get {
      storage.withHeaderPointer { Int($0.pointee.count) }
    }
    set {
      storage.withHeaderPointer { $0.pointee.count = UInt16(newValue) }
    }
  }
  
  var partialLength: Int {
    get {
      storage.withHeaderPointer { Int($0.pointee.partialLength) }
    }
    set {
      assert(newValue <= 8)
      storage.withHeaderPointer { $0.pointee.partialLength = UInt8(newValue) }
    }
  }
  
  var partialBytes: PartialBytes {
    get {
      storage.withHeaderPointer { $0.pointee.partialBytes }
    }
    set {
      storage.withHeaderPointer { $0.pointee.partialBytes = newValue }
    }
  }
  
  // Key lengths array: [keyLength[0], keyLength[1], ..., keyLength[31]]
  var keyLengths: UnsafeMutableBufferPointer<UInt16> {
    storage.withBodyPointer {
      UnsafeMutableBufferPointer(
        start: $0.assumingMemoryBound(to: UInt16.self),
        count: Self.maxEntries
      )
    }
  }
  
  // Entry data starts after key lengths array (64 bytes)
  var entryData: UnsafeMutableRawPointer {
    storage.withBodyPointer {
      $0.advanced(by: Self.keysArraySize)
    }
  }
}
```

### 6.3 Entry Layout in Packed Data

Each entry in `entryData`:
```
[keyBytes (variable length)][value (sizeof(Value))]
```

Need helper to compute offset:
```swift
// Cumulative offset to entry at index
func entryOffset(upTo index: Int) -> Int {
  var offset = 0
  for i in 0..<index {
    offset += Int(keyLengths[i]) + MemoryLayout<Value>.stride
  }
  return offset
}

// Extract key at index
func keyAt(_ index: Int) -> Key {
  assert(index < count)
  let offset = entryOffset(upTo: index)
  let keyLength = Int(keyLengths[index])
  let keyPtr = entryData.advanced(by: offset)
  return Array(
    UnsafeRawBufferPointer(start: keyPtr, count: keyLength)
  )
}

// Pointer to value at index
func valuePointer(at index: Int) -> UnsafeMutablePointer<Value> {
  let offset = entryOffset(upTo: index) + Int(keyLengths[index])
  return entryData.advanced(by: offset).assumingMemoryBound(to: Value.self)
}

// Mutable access to (key, value)
func withEntry<R>(at index: Int, body: (Key, UnsafeMutablePointer<Value>) throws -> R) rethrows -> R {
  let offset = entryOffset(upTo: index)
  let keyLength = Int(keyLengths[index])
  let key = Array(
    UnsafeRawBufferPointer(start: entryData.advanced(by: offset), count: keyLength)
  )
  let valuePtr = entryData.advanced(by: offset + keyLength).assumingMemoryBound(to: Value.self)
  return try body(key, valuePtr)
}
```

### 6.4 Lookup & Insert

```swift
extension NodeBucketLeaf {
  /// Find the index where key belongs (sorted). Returns (index, found).
  func find(keyBytes: UnsafeRawBufferPointer) -> (Int, Bool) {
    for i in 0..<count {
      let cmp = compareKeyAt(i, with: keyBytes)
      if cmp == 0 { return (i, true) }
      if cmp > 0 { return (i, false) }  // keyBytes < stored key[i]
    }
    return (count, false)  // insert at end
  }
  
  private func compareKeyAt(_ index: Int, with other: UnsafeRawBufferPointer) -> Int {
    let myKeyLength = Int(keyLengths[index])
    let otherLength = other.count
    let minLen = min(myKeyLength, otherLength)
    
    let myKeyPtr = entryData.advanced(by: entryOffset(upTo: index))
    let cmp = memcmp(myKeyPtr, other.baseAddress, minLen)
    if cmp != 0 { return cmp }
    
    // Keys equal up to minLen; shorter is less
    return myKeyLength - otherLength
  }
  
  /// Insert at sorted index (bucket must not be full).
  mutating func insert(at index: Int, keyBytes: UnsafeRawBufferPointer, value: Value) -> Bool {
    guard count < Self.maxEntries else { return false }
    guard index <= count else { return false }
    
    let keyLength = keyBytes.count
    
    // Calculate space needed
    let newEntrySize = keyLength + MemoryLayout<Value>.stride
    
    // Shift existing entries >= index one position right
    if index < count {
      // Shift key lengths
      for i in (index..<count).reversed() {
        keyLengths[i+1] = keyLengths[i]
      }
      
      // Shift entry data: move all data from offset(index) to end
      let fromOffset = entryOffset(upTo: index)
      let toOffset = fromOffset + newEntrySize
      let moveSize = entryOffset(upTo: count) - fromOffset
      
      // Memmove from back to front (overlapping copy)
      memmove(
        entryData.advanced(by: toOffset),
        entryData.advanced(by: fromOffset),
        moveSize
      )
    }
    
    // Write new entry
    let offset = entryOffset(upTo: index)
    keyLengths[index] = UInt16(keyLength)
    
    UnsafeMutableRawBufferPointer(
      start: entryData.advanced(by: offset),
      count: keyLength
    ).copyBytes(from: keyBytes)
    
    entryData.advanced(by: offset + keyLength)
      .assumingMemoryBound(to: Value.self)
      .pointee = value
    
    count += 1
    return true
  }
  
  /// Remove entry at index, shifting later entries left.
  mutating func remove(at index: Int) -> Value? {
    guard index < count else { return nil }
    
    let offset = entryOffset(upTo: index)
    let keyLength = Int(keyLengths[index])
    let value = entryData.advanced(by: offset + keyLength)
      .assumingMemoryBound(to: Value.self).pointee
    
    // Shift entries right of index left
    if index + 1 < count {
      keyLengths.withMemoryRebound(to: UInt8.self, capacity: 32 * 2) { buffer in
        memmove(
          buffer.baseAddress! + index * 2,
          buffer.baseAddress! + (index + 1) * 2,
          (count - index - 1) * 2
        )
      }
      
      let fromOffset = entryOffset(upTo: index + 1)
      let toOffset = offset
      let moveSize = entryOffset(upTo: count) - fromOffset
      
      memmove(entryData.advanced(by: toOffset), 
              entryData.advanced(by: fromOffset), 
              moveSize)
    }
    
    count -= 1
    return value
  }
}
```

### 6.5 Bucket Split

```swift
extension NodeBucketLeaf {
  static func split(
    full: NodeBucketLeaf,
    newKeyBytes: UnsafeRawBufferPointer,
    newValue: Value,
    at depth: Int
  ) -> (left: NodeBucketLeaf, right: NodeBucketLeaf, splitKeyByte: KeyPart) {
    // Collect all 33 entries (32 from full + 1 new)
    var allEntries: [(keyBytes: [UInt8], value: Value)] = []
    
    for i in 0..<full.count {
      allEntries.append((keyBytes: full.keyAt(i), value: full.valuePointer(at: i).pointee))
    }
    allEntries.append((keyBytes: Array(newKeyBytes), value: newValue))
    
    // Sort by key (byte-wise)
    allEntries.sort { ($0.keyBytes.lexicographicallyPrecedes($1.keyBytes)) }
    
    // Split at midpoint: left=0..15 (16 entries), right=16..32 (17 entries)
    // The split key byte comes from depth in the pivot entry
    let splitEntry = allEntries[16]
    let splitKeyByte = depth < splitEntry.keyBytes.count 
      ? splitEntry.keyBytes[depth]
      : 0xFF  // sentinel: key ends before split depth
    
    // Allocate left and right buckets
    var left = allocateEmpty()
    var right = allocateEmpty()
    
    // Populate left with 0..15
    for i in 0..<16 {
      _ = left.insert(
        at: i,
        keyBytes: UnsafeRawBufferPointer(start: allEntries[i].keyBytes.withUnsafeBytes { $0.baseAddress }, count: allEntries[i].keyBytes.count),
        value: allEntries[i].value
      )
    }
    
    // Populate right with 16..32
    for i in 0..<17 {
      _ = right.insert(
        at: i,
        keyBytes: UnsafeRawBufferPointer(start: allEntries[16+i].keyBytes.withUnsafeBytes { $0.baseAddress }, count: allEntries[16+i].keyBytes.count),
        value: allEntries[16+i].value
      )
    }
    
    return (left, right, splitKeyByte)
  }
  
  static func allocateEmpty() -> NodeBucketLeaf {
    let headerSize = NodeBucketLeafHeader.stride
    let keysSize = maxEntries * MemoryLayout<UInt16>.stride
    // Reserve space for entries: estimate based on typical key+value size
    let entrySize = maxEntries * (32 + MemoryLayout<Value>.stride)  // rough estimate
    let totalSize = headerSize + keysSize + entrySize
    
    let storage = NodeStorage<NodeBucketLeaf>.create(type: .bucketLeaf, size: totalSize)
    storage.update { bucket in
      bucket.count = 0
      bucket.partialLength = 0
    }
    return storage.node
  }
}
```

---

## 7. Integration with ARTree Dispatch

### 7.1 RawNode Updates

**File:** `Sources/ARTreeModule/ARTree/RawNode.swift`

```swift
extension RawNode {
  func clone<Spec: ARTreeSpec>(spec: Spec.Type) -> RawNode {
    switch type {
    case .leaf:
      return NodeStorage<NodeLeaf<Spec>>(raw: buf).clone().rawNode
    case .bucketLeaf:  // NEW
      return NodeStorage<NodeBucketLeaf<Spec>>(raw: buf).clone().rawNode
    case .node4, .node16, .node48, .node256:
      // existing cases
    }
  }
  
  func toBucketLeaf<Spec: ARTreeSpec>() -> NodeBucketLeaf<Spec> {
    assert(type == .bucketLeaf)
    return NodeBucketLeaf(buffer: buf)
  }
  
  func toARTNode<Spec: ARTreeSpec>() -> any ARTNode<Spec> {
    switch type {
    case .leaf:
      return toLeafNode()
    case .bucketLeaf:  // NEW
      return toBucketLeaf()
    default:
      return toInternalNode()
    }
  }
}
```

### 7.2 ARTree+insert Dispatch

Replace simple leaf allocation with bucket allocation by default:

```swift
// In ARTree+insert.swift
static func allocateLeaf(keyBytes key: UnsafeRawBufferPointer, value: Value) 
  -> NodeStorage<NodeBucketLeaf<Spec>>  // Changed return type
{
  NodeBucketLeaf<Spec>.allocateEmpty().storage.update { bucket in
    _ = bucket.insert(at: 0, keyBytes: key, value: value)
  }
}
```

Alternative: keep both `allocateLeaf` and `allocateBucketLeaf`, add heuristic logic to choose (e.g., always use buckets from day 1).

### 7.3 ARTree+delete Dispatch

```swift
private mutating func _delete(
  child: inout RawNode?,
  keyBytes key: UnsafeRawBufferPointer,
  depth: Int,
  isUniquePath: Bool
) -> UpdateResult<RawNode?> {
  guard let c = child else { return .noop }
  
  switch c.type {
  case .leaf:
    // existing code
    
  case .bucketLeaf:
    let bucket: NodeBucketLeaf<Spec> = c.toBucketLeaf()
    let (index, found) = bucket.find(keyBytes: key)
    guard found else { return .noop }
    
    if !isUniquePath {
      // Clone bucket before mutation
      let clone = bucket.clone()
      child = clone.rawNode
      var cloneBucket: NodeBucketLeaf<Spec> = clone.node
      _ = cloneBucket.remove(at: index)
      if cloneBucket.count == 0 {
        return .replaceWith(nil)
      }
      return .noop
    }
    
    _ = bucket.remove(at: index)
    if bucket.count == 0 {
      return .replaceWith(nil)
    }
    return .noop
    
  case .node4, .node16, .node48, .node256:
    // existing code
  }
}
```

---

## 8. COW Safety Analysis

### 8.1 Unique Path Tracking

Bucketed leaves must participate in COW the same way single-leaf nodes do:

1. **Insert path:**
   - `_findInsertNode` walks from root, checking `isKnownUniquelyReferenced` at each step
   - When reaching a bucket leaf, if not unique, clone it before calling `insert()`
   - ✓ Same pattern as current leaves

2. **Delete path:**
   - `updateChild` uses `withSelfOrClone(isUnique:)` before mutating child
   - If child is a bucket, clone before remove
   - ✓ Same pattern

3. **Key invariant:**
   - A bucket is only mutated if it's on the unique path from root
   - Path compression still works: if parent node has one child, merge prefixes

### 8.2 Deallocation Safety

```swift
extension NodeBucketLeaf: ARTNode {
  final class Buffer: RawNodeBuffer {
    deinit {
      // Deinit all values in bucket
      let bucket = NodeBucketLeaf<Spec>(buffer: self)
      for i in 0..<bucket.count {
        bucket.valuePointer(at: i).deinitialize(count: 1)
      }
    }
  }
  
  func clone() -> NodeStorage<Self> {
    // Copy bucket structure and all entries
    let cloned = Self.allocateEmpty()
    cloned.read { newBucket in
      for i in 0..<self.count {
        let (key, value) = self.withEntry(at: i) { k, v in
          (k, v.pointee)
        }
        _ = newBucket.insert(at: i, keyBytes: key.withUnsafeBytes { $0 }, value: value)
      }
    }
    return cloned.storage
  }
}
```

---

## 9. Testing Strategy

### 9.1 Unit Tests

**File:** `Tests/ARTreeModuleTests/NodeBucketLeafTests.swift`

```swift
@Test("Insert maintains order")
func insertOrder() {
  var bucket = NodeBucketLeaf<DefaultSpec<Int>>.allocateEmpty()
  for byte in [2, 0, 3, 1] {
    let key = [byte]
    _ = bucket.insert(at: ..., keyBytes: UnsafeRawBufferPointer(...), value: Int(byte))
  }
  // Verify sorted order
}

@Test("Fill bucket to capacity")
func fillAndSplit() {
  var bucket = NodeBucketLeaf<...>()
  for i in 0..<32 {
    _ = bucket.insert(at: i, ...)
  }
  assert(bucket.count == 32)
  
  // Try to insert 33rd: should fail
  let canInsert = bucket.insert(at: 32, ...)
  assertFalse(canInsert)
}

@Test("Bucket split preserves all entries")
func split() {
  var bucket = NodeBucketLeaf<...>.allocateEmpty()
  // Fill with 32 entries
  let (left, right, splitKey) = NodeBucketLeaf.split(...)
  assert(left.count + right.count == 33)
  // Verify order, keys in correct half
}

@Test("Delete maintains integrity")
func delete() {
  // Insert several, delete middle, verify order
}
```

### 9.2 Integration Tests

**File:** `Tests/ARTreeModuleTests/IntegrationTests.swift` (expanded)

```swift
@Test("Tree with bucketed leaves")
func treeWithBuckets() {
  var tree: ARTree<Int> = [:]
  
  // Insert keys that hash to same prefix, trigger bucket split
  for i in 0..<40 {
    tree[[UInt8(i)]] = i
  }
  
  // Verify all present
  for i in 0..<40 {
    assert(tree[[UInt8(i)]] == i)
  }
  
  // Verify iteration order
  var count = 0
  for (_, _) in tree {
    count += 1
  }
  assert(count == 40)
  
  // Delete half
  for i in 0..<20 {
    tree.delete(key: [UInt8(i)])
  }
  
  // Verify remaining
  assert(tree.count == 20)
}

@Test("COW with bucket leaves")
func cowWithBuckets() {
  var tree1: ARTree<Int> = [:]
  for i in 0..<16 {
    tree1[[UInt8(i)]] = i
  }
  
  var tree2 = tree1  // Shallow copy
  
  tree2[[UInt8(0)]] = 999  // Mutate copy
  
  assert(tree1[[UInt8(0)]] == 0)  // Original unchanged
  assert(tree2[[UInt8(0)]] == 999)
  
  // Both trees still valid
  assert(tree1.count == 16)
  assert(tree2.count == 16)
}
```

### 9.3 Simulation Tests

**Extend `Tests/ARTreeModuleTests/Simulation/`:**
- Modify `Simulator.swift` to optionally use bucket leaves
- Run existing simulation (random ops) with buckets
- Verify structural invariants, COW correctness, iteration order

---

## 10. Performance Considerations

### 10.1 Space Efficiency

**Current (single-leaf):**
- Tree overhead: 4 nodes × (16 + 4*9 + 4*8) = ~800 bytes per level
- Leaves: 4 + keyLength + sizeof(Value) per entry
- High space cost from many small leaves

**Bucketed (32 per leaf):**
- Bucket overhead: 16 + 64 = 80 bytes once, then ~20 bytes per entry
- ~40–50% reduction in tree height
- ~10–20% overall space reduction for typical workloads (32-byte keys)

### 10.2 Time Complexity

| Operation | Single-Leaf | Bucketed (32 entries) |
|-----------|------------|----------------------|
| Insert    | O(log n)   | O(log n / log 32) + O(32) = O(log n / 5 + 32) |
| Lookup    | O(log n)   | O(log n / 5) + O(32) |
| Delete    | O(log n)   | O(log n / 5) + O(32) |
| Iterate   | O(n)       | O(n) (same, n entries total) |

Linear search within bucket (32 iterations) is negligible vs tree operations (log n, n >> 32).

### 10.3 Hot Path Optimizations

1. **SIMD key comparisons in bucket lookup:**
   - Load multiple key lengths via SIMD, compare in parallel
   - Only 32 entries, but vectorization useful for batch operations

2. **Memmove efficiency:**
   - Shifting during insert/delete uses platform memmove (optimized)
   - Overlapping moves safe when shifting right-to-left or left-to-right appropriately

3. **Bucket split batching:**
   - When a tree reaches a certain size, batching splits could optimize allocations
   - Deferred for later optimization

---

## 11. Rollout Strategy

### Phased Deployment

**Phase 1:** Feature flag
- Add `USE_BUCKETED_LEAVES` conditional compilation flag
- Only enable for new tests initially

**Phase 2:** Gradual enable
- Enable by default in test suites
- Run full simulation suite with bucketed leaves
- Monitor for regressions

**Phase 3:** Production
- Remove feature flag, make bucketed leaves the only leaf type
- Keep `NodeLeaf` type for backward compatibility (deprecated)
- Update docs/benchmarks

---

## 12. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Memory layout errors in bucket entry shift | Corruption, crashes | Unit tests with varied key sizes, AddressSanitizer |
| Deinit omission in split bucket | Memory leak | Explicit deinit in clone, test with LifetimeTracked values |
| Order invariant violation | Silent correctness bug | Iteration tests verify sorted order, simulation checks |
| COW path missed (bucket modified when shared) | Data corruption across copies | COW tests with shallow copies, Const.testCheckUnique flag |
| Bucket split doesn't preserve all 33 entries | Data loss | Unit test with explicit count assertion |
| Path compression merges fail for buckets | Tree corruption | Path compression tests with bucket nodes |

---

## 13. Code Review Checklist

Before merging each phase:

- [ ] All unit tests pass (new node type, operations)
- [ ] Integration tests verify COW semantics
- [ ] Simulation suite completes without errors
- [ ] Memory sanitizers (AddressSanitizer) pass
- [ ] Iteration order verified (sorted, no duplicates)
- [ ] Deinit called for all values in bucket
- [ ] Clone creates independent buckets
- [ ] Bucket split creates exactly 33 entries across left+right
- [ ] Uniqueness checks prevent shared bucket mutation
- [ ] No spurious ref counts in COW path

---

## 14. File Structure Summary

### New Files
- `Sources/ARTreeModule/ARTree/NodeBucketLeaf.swift` (500 lines)
  - Header, struct definition, accessors, find/insert/remove, split
- `Tests/ARTreeModuleTests/NodeBucketLeafTests.swift` (300 lines)
  - Unit tests for all operations

### Modified Files
| File | Changes |
|------|---------|
| `NodeType.swift` | Add `.bucketLeaf` case |
| `RawNode.swift` | Add `.bucketLeaf` dispatch in clone/toXXX methods |
| `ARTree+insert.swift` | Dispatch bucketLeaf in InsertAction, allocateBucketLeaf |
| `ARTree+delete.swift` | Dispatch bucketLeaf in _delete |
| `ARTree+Sequence.swift` | Handle bucketLeaf in iterator |
| `ARTree.Index.swift` | Update path tracking if needed |

Total new code: ~1000 lines (NodeBucketLeaf + tests)
Total modified lines: ~100 lines (dispatch additions)

---

## 15. Performance Benchmarks to Add

Once implementation is complete:

```swift
@Benchmark("Insert 1000 keys into bucketed tree")
func benchInsertBucketed() {
  var tree: ARTree<Int> = [:]
  for i in 0..<1000 {
    tree[[UInt8(i & 0xFF), UInt8(i >> 8)]] = i
  }
}

@Benchmark("Range scan with buckets")
func benchRangeScan() {
  var tree: ARTree<Int> = [:]
  for i in 0..<10000 {
    tree[[UInt8(i & 0xFF), UInt8(i >> 8)]] = i
  }
  var sum = 0
  for (_, v) in tree {
    sum += v
  }
}

@Benchmark("COW copy with buckets")
func benchCOWCopy() {
  var tree1: ARTree<Int> = [:]
  for i in 0..<5000 {
    tree1[[UInt8(i & 0xFF), UInt8(i >> 8)]] = i
  }
  let tree2 = tree1  // Shallow copy
  tree2[[UInt8(0), UInt8(0)]] = 999  // Trigger COW
}
```

Compare before/after for:
- Memory usage
- Insert throughput
- Iteration speed
- COW copy time (should be identical)
- Tree depth (should be shallower)

