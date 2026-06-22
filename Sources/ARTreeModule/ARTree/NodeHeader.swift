typealias PartialBytes = FixedArray8<UInt8>

struct InternalNodeHeader {
  var count: UInt16 = 0
  var partialLength: UInt8 = 0
  var partialBytes: PartialBytes = PartialBytes(repeating: 0)
}
