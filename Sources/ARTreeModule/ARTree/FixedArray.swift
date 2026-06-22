typealias FixedArray4<T> = FixedArray<FixedArrayStorage4<T>>
typealias FixedArray8<T> = FixedArray<FixedArrayStorage8<T>>
typealias FixedArray16<T> = FixedArray<FixedArrayStorage16<T>>
typealias FixedArray48<T> = FixedArray<FixedArrayStorage48<T>>
typealias FixedArray256<T> = FixedArray<FixedArrayStorage256<T>>

internal struct FixedArray<Storage: FixedArrayStorage> {
  typealias Element = Storage.Element
  internal var storage: Storage
}

extension FixedArray {
  @inline(__always)
  init(repeating: Element) {
    self.storage = Storage(repeating: (repeating))
  }
}

extension FixedArray {
  internal static var capacity: Int {
    @inline(__always) get { return Storage.capacity }
  }

  internal var capacity: Int {
    @inline(__always) get { return Self.capacity }
  }
}
