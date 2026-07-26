//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift ART open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

/// A leaf node that stores multiple key-value pairs in a sorted bucket.
/// This reduces memory overhead and improves cache locality compared to
/// individual leaf nodes per entry.
@usableFromInline
struct NodeBucketLeaf<Spec: ARTreeSpec> {
  typealias Value = Spec.Value

  /// Maximum number of entries per bucket
  static var capacity: Int { 32 }

  var storage: Storage
}

// MARK: - Type and Constants

extension NodeBucketLeaf {
  static var type: NodeType { .bucketLeaf }

  /// Size of the fixed header (count + partial info + key lengths)
  static var headerSize: Int {
    MemoryLayout<UInt8>.stride +           // count
    MemoryLayout<UInt8>.stride +           // partialLength
    8 +                                     // partialBytes
    capacity * MemoryLayout<UInt16>.stride // key lengths
  }
}

// MARK: - Header Access

extension NodeBucketLeaf {
  /// Number of entries in the bucket
  var count: Int {
    get {
      storage.withUnsafePointer {
        Int($0.assumingMemoryBound(to: UInt8.self).pointee)
      }
    }
    set {
      storage.withUnsafePointer {
        $0.assumingMemoryBound(to: UInt8.self).pointee = UInt8(newValue)
      }
    }
  }

  /// Length of shared partial key prefix
  var partialLength: Int {
    get {
      storage.withUnsafePointer {
        Int($0.advanced(by: 1).assumingMemoryBound(to: UInt8.self).pointee)
      }
    }
    set {
      storage.withUnsafePointer {
        $0.advanced(by: 1).assumingMemoryBound(to: UInt8.self).pointee = UInt8(newValue)
      }
    }
  }

  /// Shared partial key prefix (up to 8 bytes)
  var partialBytes: UnsafeMutableBufferPointer<UInt8> {
    storage.withUnsafePointer {
      UnsafeMutableBufferPointer(
        start: $0.advanced(by: 2).assumingMemoryBound(to: UInt8.self),
        count: 8
      )
    }
  }

  /// Array of key lengths for each entry
  var keyLengths: UnsafeMutableBufferPointer<UInt16> {
    storage.withUnsafePointer {
      UnsafeMutableBufferPointer(
        start: $0.advanced(by: 10).assumingMemoryBound(to: UInt16.self),
        count: Self.capacity
      )
    }
  }

  /// Pointer to start of entry data (keys and values)
  var entryDataPtr: UnsafeMutableRawPointer {
    storage.withUnsafePointer {
      $0.advanced(by: Self.headerSize)
    }
  }
}

// MARK: - Allocation

extension NodeBucketLeaf {
  /// Allocate an empty bucket leaf
  static func allocate() -> NodeStorage<Self> {
    let initialSize = headerSize + 256  // Start with 256 bytes for entries
    let storage = NodeStorage<NodeBucketLeaf>.create(type: .bucketLeaf, size: initialSize)

    storage.update { leaf in
      leaf.count = 0
      leaf.partialLength = 0
      // Initialize key lengths to 0
      for i in 0..<capacity {
        leaf.keyLengths[i] = 0
      }
    }

    return storage
  }

  /// Allocate a bucket with a single entry
  static func allocate(key: Key, value: Value) -> NodeStorage<Self> {
    key.withUnsafeBytes { allocate(keyBytes: $0, value: value) }
  }

  static func allocate(keyBytes: UnsafeRawBufferPointer, value: Value) -> NodeStorage<Self> {
    let entrySize = keyBytes.count + MemoryLayout<Value>.stride
    let totalSize = headerSize + entrySize
    let storage = NodeStorage<NodeBucketLeaf>.create(type: .bucketLeaf, size: totalSize)

    storage.update { leaf in
      leaf.count = 1
      leaf.partialLength = 0
      leaf.keyLengths[0] = UInt16(keyBytes.count)

      // Copy key and value
      let dataPtr = leaf.entryDataPtr
      dataPtr.copyMemory(from: keyBytes.baseAddress!, byteCount: keyBytes.count)
      dataPtr.advanced(by: keyBytes.count)
        .assumingMemoryBound(to: Value.self)
        .pointee = value
    }

    return storage
  }

  /// Create a new bucket from an old single-entry leaf
  static func allocate(from oldLeaf: NodeLeaf<Spec>) -> NodeStorage<Self> {
    let oldKey = oldLeaf.key
    let oldValue = oldLeaf.value
    return allocate(key: oldKey, value: oldValue)
  }
}

// MARK: - Entry Access

extension NodeBucketLeaf {
  /// Calculate offset to entry data for given index
  func entryOffset(at index: Int) -> Int {
    var offset = 0
    for i in 0..<index {
      offset += Int(keyLengths[i]) + MemoryLayout<Value>.stride
    }
    return offset
  }

  /// Get key at index
  func key(at index: Int) -> Key {
    precondition(index < count, "Index out of bounds")
    let offset = entryOffset(at: index)
    let length = Int(keyLengths[index])

    return Array(UnsafeRawBufferPointer(
      start: entryDataPtr.advanced(by: offset),
      count: length
    ))
  }

  /// Get key bytes at index
  func withKeyBytes<R>(at index: Int, _ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
    precondition(index < count, "Index out of bounds")
    let offset = entryOffset(at: index)
    let length = Int(keyLengths[index])

    return try body(UnsafeRawBufferPointer(
      start: entryDataPtr.advanced(by: offset),
      count: length
    ))
  }

  /// Get value at index
  func value(at index: Int) -> Value {
    precondition(index < count, "Index out of bounds")
    let offset = entryOffset(at: index)
    let keyLength = Int(keyLengths[index])

    return entryDataPtr
      .advanced(by: offset + keyLength)
      .assumingMemoryBound(to: Value.self)
      .pointee
  }

  /// Get mutable value reference at index
  mutating func withValue<R>(at index: Int, _ body: (inout Value) throws -> R) rethrows -> R {
    precondition(index < count, "Index out of bounds")
    let offset = entryOffset(at: index)
    let keyLength = Int(keyLengths[index])

    return try body(&entryDataPtr
      .advanced(by: offset + keyLength)
      .assumingMemoryBound(to: Value.self)
      .pointee)
  }
}

// MARK: - Search Operations

extension NodeBucketLeaf {
  /// Find index for key using linear search
  func findIndex(for key: Key, depth: Int = 0) -> Int? {
    key.withUnsafeBytes { findIndex(for: $0, depth: depth) }
  }

  func findIndex(for keyBytes: UnsafeRawBufferPointer, depth: Int = 0) -> Int? {
    // Linear search through sorted entries
    for i in 0..<count {
      let cmp = withKeyBytes(at: i) { entryKey in
        compareKeys(keyBytes, entryKey, fromIndex: depth)
      }

      if cmp == 0 {
        return i  // Found exact match
      } else if cmp < 0 {
        return nil  // Key would be before this entry
      }
    }
    return nil  // Key would be after all entries
  }

  /// Find insertion index for key (where it should be inserted to maintain order)
  func insertionIndex(for key: Key, depth: Int = 0) -> Int {
    key.withUnsafeBytes { insertionIndex(for: $0, depth: depth) }
  }

  func insertionIndex(for keyBytes: UnsafeRawBufferPointer, depth: Int = 0) -> Int {
    for i in 0..<count {
      let cmp = withKeyBytes(at: i) { entryKey in
        compareKeys(keyBytes, entryKey, fromIndex: depth)
      }

      if cmp <= 0 {
        return i  // Insert before or replace this entry
      }
    }
    return count  // Insert at end
  }

  /// Compare two keys starting from given index
  private func compareKeys(_ k1: UnsafeRawBufferPointer, _ k2: UnsafeRawBufferPointer, fromIndex: Int) -> Int {
    let len1 = k1.count - fromIndex
    let len2 = k2.count - fromIndex
    let minLen = min(len1, len2)

    for i in 0..<minLen {
      let b1 = k1[fromIndex + i]
      let b2 = k2[fromIndex + i]
      if b1 < b2 { return -1 }
      if b1 > b2 { return 1 }
    }

    // Equal up to minLen, shorter key is less
    if len1 < len2 { return -1 }
    if len1 > len2 { return 1 }
    return 0
  }
}

// MARK: - Mutations

extension NodeBucketLeaf {
  /// Insert or update entry at index
  mutating func setEntry(at index: Int, key: Key, value: Value) {
    key.withUnsafeBytes { setEntry(at: index, keyBytes: $0, value: value) }
  }

  mutating func setEntry(at index: Int, keyBytes: UnsafeRawBufferPointer, value: Value) {
    precondition(index <= count, "Index out of bounds")

    if index < count && keyLengths[index] == keyBytes.count {
      // Same key length - can update in place
      let offset = entryOffset(at: index)
      entryDataPtr.advanced(by: offset)
        .copyMemory(from: keyBytes.baseAddress!, byteCount: keyBytes.count)
      entryDataPtr.advanced(by: offset + keyBytes.count)
        .assumingMemoryBound(to: Value.self)
        .pointee = value
    } else {
      // Need to resize - this requires reallocation
      // For now, we'll implement a simple version that works
      fatalError("Entry resizing not yet implemented")
    }
  }

  /// Remove entry at index
  mutating func removeEntry(at index: Int) {
    precondition(index < count, "Index out of bounds")

    // Calculate data to shift
    let currentOffset = entryOffset(at: index)
    let currentSize = Int(keyLengths[index]) + MemoryLayout<Value>.stride
    let nextOffset = currentOffset + currentSize
    let remainingSize = entryOffset(at: count) - nextOffset

    // Shift remaining entries left
    if remainingSize > 0 {
      entryDataPtr.advanced(by: currentOffset)
        .copyMemory(from: entryDataPtr.advanced(by: nextOffset), byteCount: remainingSize)
    }

    // Shift key lengths
    for i in index..<(count - 1) {
      keyLengths[i] = keyLengths[i + 1]
    }

    count -= 1
  }

  /// Check if bucket needs splitting
  var needsSplit: Bool {
    count >= Self.capacity
  }

  /// Split bucket into two
  func split() -> (NodeStorage<Self>, NodeStorage<Self>) {
    let mid = count / 2

    // Calculate sizes for both buckets
    var size1 = 0
    for i in 0..<mid {
      size1 += Int(keyLengths[i]) + MemoryLayout<Value>.stride
    }

    var size2 = 0
    for i in mid..<count {
      size2 += Int(keyLengths[i]) + MemoryLayout<Value>.stride
    }

    // Create first bucket with first half
    let bucket1 = NodeStorage<NodeBucketLeaf>.create(type: .bucketLeaf, size: Self.headerSize + size1)
    bucket1.update { leaf in
      leaf.count = mid
      leaf.partialLength = self.partialLength

      // Copy partial bytes
      for i in 0..<8 {
        leaf.partialBytes[i] = self.partialBytes[i]
      }

      // Copy key lengths and data
      var offset = 0
      for i in 0..<mid {
        leaf.keyLengths[i] = self.keyLengths[i]
        let entrySize = Int(self.keyLengths[i]) + MemoryLayout<Value>.stride
        leaf.entryDataPtr.advanced(by: offset)
          .copyMemory(from: self.entryDataPtr.advanced(by: self.entryOffset(at: i)),
                      byteCount: entrySize)
        offset += entrySize
      }
    }

    // Create second bucket with second half
    let bucket2 = NodeStorage<NodeBucketLeaf>.create(type: .bucketLeaf, size: Self.headerSize + size2)
    bucket2.update { leaf in
      leaf.count = count - mid
      leaf.partialLength = self.partialLength

      // Copy partial bytes
      for i in 0..<8 {
        leaf.partialBytes[i] = self.partialBytes[i]
      }

      // Copy key lengths and data
      var offset = 0
      for i in mid..<count {
        leaf.keyLengths[i - mid] = self.keyLengths[i]
        let entrySize = Int(self.keyLengths[i]) + MemoryLayout<Value>.stride
        leaf.entryDataPtr.advanced(by: offset)
          .copyMemory(from: self.entryDataPtr.advanced(by: self.entryOffset(at: i)),
                      byteCount: entrySize)
        offset += entrySize
      }
    }

    return (bucket1, bucket2)
  }
}

// MARK: - ARTNode Conformance

extension NodeBucketLeaf: ARTNode {
  final class Buffer: RawNodeBuffer {
    deinit {
      let leaf = NodeBucketLeaf(buffer: self)
      // Deinitialize all values
      for i in 0..<leaf.count {
        let offset = leaf.entryOffset(at: i)
        let keyLength = Int(leaf.keyLengths[i])
        _ = leaf.entryDataPtr
          .advanced(by: offset + keyLength)
          .assumingMemoryBound(to: Value.self)
          .deinitialize(count: 1)
      }
    }
  }

  func clone() -> NodeStorage<Self> {
    // Calculate total data size
    var totalDataSize = 0
    for i in 0..<count {
      totalDataSize += Int(keyLengths[i]) + MemoryLayout<Value>.stride
    }

    let newStorage = NodeStorage<NodeBucketLeaf>.create(type: .bucketLeaf, size: Self.headerSize + totalDataSize)

    newStorage.update { newLeaf in
      // Copy header
      newLeaf.count = self.count
      newLeaf.partialLength = self.partialLength

      // Copy partial bytes
      for i in 0..<8 {
        newLeaf.partialBytes[i] = self.partialBytes[i]
      }

      // Copy key lengths
      for i in 0..<Self.capacity {
        newLeaf.keyLengths[i] = self.keyLengths[i]
      }

      // Copy entry data
      newLeaf.entryDataPtr.copyMemory(from: self.entryDataPtr, byteCount: totalDataSize)
    }

    return newStorage
  }
}