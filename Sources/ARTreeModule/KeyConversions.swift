public protocol ConvertibleToBinaryComparableBytes {
  func withUnsafeBinaryComparableBytes<R>(
    _ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R
  static func fromBinaryComparableBytes(_ bytes: [UInt8]) -> Self

  /// Decode a value from its binary-comparable bytes without requiring a `[UInt8]`.
  /// Used on the iteration hot path to avoid materializing an array per element.
  static func fromBinaryComparableBytes(_ bytes: UnsafeRawBufferPointer) -> Self
}

extension ConvertibleToBinaryComparableBytes {
  public func toBinaryComparableBytes() -> [UInt8] {
    self.withUnsafeBinaryComparableBytes { Array($0) }
  }

  // Default: fall back to the array decoder. Conformers with a cheap direct
  // decode (integers, strings) override this to skip the allocation.
  public static func fromBinaryComparableBytes(_ bytes: UnsafeRawBufferPointer) -> Self {
    fromBinaryComparableBytes(Array(bytes))
  }
}

///-- Unsigned Integers ----------------------------------------------------------------------//

extension UInt: ConvertibleToBinaryComparableBytes {
  public func withUnsafeBinaryComparableBytes<R>(
    _ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
    try withUnsafeBytes(of: self.bigEndian) {
      try body($0)
    }
  }

  public static func fromBinaryComparableBytes(_ bytes: [UInt8]) -> Self {
    let ii = bytes.withUnsafeBytes {
        $0.assumingMemoryBound(to: Self.self).baseAddress!.pointee
      }
    return Self(bigEndian: ii)
  }
}

extension UInt16: ConvertibleToBinaryComparableBytes {
  public func withUnsafeBinaryComparableBytes<R>(
    _ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
    try withUnsafeBytes(of: self.bigEndian) {
      try body($0)
    }
  }

  public static func fromBinaryComparableBytes(_ bytes: [UInt8]) -> Self {
    let ii = bytes.withUnsafeBytes {
        $0.assumingMemoryBound(to: Self.self).baseAddress!.pointee
      }
    return Self(bigEndian: ii)
  }
}

extension UInt32: ConvertibleToBinaryComparableBytes {
  public func withUnsafeBinaryComparableBytes<R>(
    _ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
    try withUnsafeBytes(of: self.bigEndian) {
      try body($0)
    }
  }

  public static func fromBinaryComparableBytes(_ bytes: [UInt8]) -> Self {
    let ii = bytes.withUnsafeBytes {
        $0.assumingMemoryBound(to: Self.self).baseAddress!.pointee
      }
    return Self(bigEndian: ii)
  }
}

extension UInt64: ConvertibleToBinaryComparableBytes {
  public func withUnsafeBinaryComparableBytes<R>(
    _ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
    try withUnsafeBytes(of: self.bigEndian) {
      try body($0)
    }
  }

  public static func fromBinaryComparableBytes(_ bytes: [UInt8]) -> Self {
    let ii = bytes.withUnsafeBytes {
        $0.assumingMemoryBound(to: Self.self).baseAddress!.pointee
      }
    return Self(bigEndian: ii)
  }
}

///-- Signed Integers ------------------------------------------------------------------------//

fileprivate func _flipSignBit<T: SignedInteger & FixedWidthInteger>(_ val: T) -> T {
  return val ^ (1 << (T.bitWidth - 1))
}

extension Int: ConvertibleToBinaryComparableBytes {
  public func withUnsafeBinaryComparableBytes<R>(
    _ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
    let ii = _flipSignBit(self).bigEndian
    return try withUnsafeBytes(of: ii) {
      try body($0)
    }
  }

  public static func fromBinaryComparableBytes(_ bytes: [UInt8]) -> Self {
    let ii = bytes.withUnsafeBytes {
        $0.assumingMemoryBound(to: Self.self).baseAddress!.pointee
      }
    return _flipSignBit(Self(bigEndian: ii))
  }
}

extension Int32: ConvertibleToBinaryComparableBytes {
  public func withUnsafeBinaryComparableBytes<R>(
    _ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
    let ii = _flipSignBit(self).bigEndian
    return try withUnsafeBytes(of: ii) {
      try body($0)
    }
  }

  public static func fromBinaryComparableBytes(_ bytes: [UInt8]) -> Self {
    let ii = bytes.withUnsafeBytes {
        $0.assumingMemoryBound(to: Self.self).baseAddress!.pointee
      }
    return _flipSignBit(Self(bigEndian: ii))
  }
}

extension Int64: ConvertibleToBinaryComparableBytes {
  public func withUnsafeBinaryComparableBytes<R>(
    _ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
    let ii = _flipSignBit(self).bigEndian
    return try withUnsafeBytes(of: ii) {
      try body($0)
    }
  }

  public static func fromBinaryComparableBytes(_ bytes: [UInt8]) -> Self {
    let ii = bytes.withUnsafeBytes {
        $0.assumingMemoryBound(to: Self.self).baseAddress!.pointee
      }
    return _flipSignBit(Self(bigEndian: ii))
  }
}

///-- String ---------------------------------------------------------------------------------//

extension String: ConvertibleToBinaryComparableBytes {
  public func withUnsafeBinaryComparableBytes<R>(
    _ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {

    try self.utf8CString.withUnsafeBytes {
      try body($0)
    }
  }

  public static func fromBinaryComparableBytes(_ bytes: [UInt8]) -> Self {
    String(cString: bytes)
  }

  public static func fromBinaryComparableBytes(_ bytes: UnsafeRawBufferPointer) -> Self {
    // Bytes are the UTF-8 encoding plus a trailing NUL; drop it before decoding.
    String(decoding: bytes.prefix(Swift.max(0, bytes.count - 1)), as: UTF8.self)
  }
}

///-- Direct (allocation-free) integer decoders ----------------------------------------------//
// Used by iteration to rebuild keys straight from a leaf's bytes, skipping the
// `[UInt8]` the array-based decoder would allocate per element.

extension UInt {
  public static func fromBinaryComparableBytes(_ bytes: UnsafeRawBufferPointer) -> Self {
    Self(bigEndian: bytes.loadUnaligned(as: Self.self))
  }
}

extension UInt16 {
  public static func fromBinaryComparableBytes(_ bytes: UnsafeRawBufferPointer) -> Self {
    Self(bigEndian: bytes.loadUnaligned(as: Self.self))
  }
}

extension UInt32 {
  public static func fromBinaryComparableBytes(_ bytes: UnsafeRawBufferPointer) -> Self {
    Self(bigEndian: bytes.loadUnaligned(as: Self.self))
  }
}

extension UInt64 {
  public static func fromBinaryComparableBytes(_ bytes: UnsafeRawBufferPointer) -> Self {
    Self(bigEndian: bytes.loadUnaligned(as: Self.self))
  }
}

extension Int {
  public static func fromBinaryComparableBytes(_ bytes: UnsafeRawBufferPointer) -> Self {
    _flipSignBit(Self(bigEndian: bytes.loadUnaligned(as: Self.self)))
  }
}

extension Int32 {
  public static func fromBinaryComparableBytes(_ bytes: UnsafeRawBufferPointer) -> Self {
    _flipSignBit(Self(bigEndian: bytes.loadUnaligned(as: Self.self)))
  }
}

extension Int64 {
  public static func fromBinaryComparableBytes(_ bytes: UnsafeRawBufferPointer) -> Self {
    _flipSignBit(Self(bigEndian: bytes.loadUnaligned(as: Self.self)))
  }
}

///-- Bytes ----------------------------------------------------------------------------------//

// TODO: Disable until, we support storing bytes with shared prefixes.
// extension [UInt8]: ConvertibleToBinaryComparableBytes {
//   public func toBinaryComparableBytes() -> [UInt8] {
//     return self
//   }

//   public static func fromBinaryComparableBytes(_ bytes: [UInt8]) -> Key {
//     return bytes
//   }
// }
