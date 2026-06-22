struct UnmanagedNodeStorage<Mn: ARTNode> {
  var ref: Unmanaged<Mn.Buffer>
}

extension UnmanagedNodeStorage {
  init(raw: RawNodeBuffer) {
    self.ref = .passUnretained(unsafeDowncast(raw, to: Mn.Buffer.self))
  }
}

extension UnmanagedNodeStorage {
  @inlinable @inline(__always)
  internal func withRaw<R>(_ body: (Mn.Buffer) throws -> R) rethrows -> R {
    try ref._withUnsafeGuaranteedRef(body)
  }

  func withUnsafePointer<R>(_ body: (UnsafeMutableRawPointer) throws -> R) rethrows -> R {
    try withRaw { buf in
      try buf.withUnsafeMutablePointerToElements {
        try body(UnsafeMutableRawPointer($0))
      }
    }
  }
}

extension UnmanagedNodeStorage where Mn: InternalNode {
  typealias Header = Mn.Header

  func withHeaderPointer<R>(_ body: (UnsafeMutablePointer<Header>) throws -> R) rethrows -> R {
    try withRaw { buf in
      try buf.withUnsafeMutablePointerToElements {
        try body(UnsafeMutableRawPointer($0).assumingMemoryBound(to: Header.self))
      }
    }
  }

  func withBodyPointer<R>(_ body: (UnsafeMutableRawPointer) throws -> R) rethrows -> R {
    try withRaw { buf in
      try buf.withUnsafeMutablePointerToElements {
        try body(UnsafeMutableRawPointer($0).advanced(by: MemoryLayout<Header>.stride))
      }
    }
  }
}
