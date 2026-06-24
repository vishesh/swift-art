extension FixedArray {
  @inlinable
  @inline(__always)
  mutating func copy(src: ArraySlice<Element>, start: Int, count: Int) {
    // TODO: memcpy?
    for ii in 0..<Swift.min(Self.capacity, count) {
      self[ii] = src[src.startIndex + start + ii]
    }
  }

  @inlinable
  @inline(__always)
  mutating func copy(src: UnsafeMutableBufferPointer<Element>, start: Int, count: Int) {
    for ii in 0..<Swift.min(Self.capacity, count) {
      self[ii] = src[start + ii]
    }
  }

  @inlinable
  @inline(__always)
  mutating func copy(src: UnsafeRawBufferPointer, start: Int, count: Int) where Element == UInt8 {
    for ii in 0..<Swift.min(Self.capacity, count) {
      self[ii] = src[start + ii]
    }
  }

  @inlinable
  @inline(__always)
  mutating func shiftLeft(toIndex: Int) {
    for ii in toIndex..<Self.capacity {
      self[ii - toIndex] = self[ii]
    }
  }

  @inlinable
  @inline(__always)
  mutating func shiftRight() {
    for ii in (1..<Self.capacity).reversed() {
      self[ii] = self[ii - 1]
    }
  }
}
