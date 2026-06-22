import Testing
@testable import ARTreeModule

// Binds `Const.testCheckUnique` to true for the duration of each test in the
// suite, scoped to the test's task so it can't leak into parallel suites.
struct UniquePathTrait: SuiteTrait, TestScoping {
  func provideScope(
    for test: Test,
    testCase: Test.Case?,
    performing function: @Sendable () async throws -> Void
  ) async throws {
    try await Const.$testCheckUnique.withValue(true) {
      try await function()
    }
  }
}

extension Trait where Self == UniquePathTrait {
  static var checksUniquePath: Self { Self() }
}
