internal struct Const {
  static let maxPartialLength = 8
  @TaskLocal static var testCheckUnique = false
  nonisolated(unsafe) static var testPrintRc = false
  nonisolated(unsafe) static var testPrintAddr = false
}

public protocol ARTreeSpec {
  associatedtype Value
}

public struct DefaultSpec<_Value>: ARTreeSpec {
  public typealias Value = _Value
}
