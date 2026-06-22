internal struct Const {
  static let maxPartialLength = 8
  static var testCheckUnique = false
  static var testPrintRc = false
  static var testPrintAddr = false
}

public protocol ARTreeSpec {
  associatedtype Value
}

public struct DefaultSpec<_Value>: ARTreeSpec {
  public typealias Value = _Value
}
