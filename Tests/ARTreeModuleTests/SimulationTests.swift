import Testing
import _CollectionsTestSupport
@testable import ARTreeModule

#if canImport(Foundation)
import Foundation
#endif

private let simulationSeeds: [UInt64] = Array(0..<8)
private let uniqueOwnerSeeds: [UInt64] = Array(0..<6)

/// Long randomized operation sequences with live copies taken and mutated
/// independently. Exercises the copy-on-write / reference-count machinery: every
/// snapshot must keep matching its own model, and nothing must leak.
@Suite struct ARTreeSimulationTests {
  @Test(arguments: simulationSeeds)
  func clustered(seed: UInt64) {
    runSimulation(seed: seed, config: SimulationConfig(keygenKind: .clustered))
  }

  @Test(arguments: simulationSeeds)
  func wide(seed: UInt64) {
    runSimulation(seed: seed, config: SimulationConfig(keygenKind: .wide))
  }

  @Test(arguments: simulationSeeds)
  func deep(seed: UInt64) {
    runSimulation(seed: seed, config: SimulationConfig(keygenKind: .deep))
  }
}

/// Single-owner simulation: no snapshots, so every mutation walks a uniquely-owned
/// path and the `Const.testCheckUnique` assertion (enabled by `.checksUniquePath`)
/// must hold throughout.
@Suite(.checksUniquePath) struct ARTreeUniqueOwnerSimulationTests {
  private static func config(_ kind: KeygenKind) -> SimulationConfig {
    var cfg = SimulationConfig(keygenKind: kind)
    cfg.cowEnabled = false
    return cfg
  }

  @Test(arguments: uniqueOwnerSeeds)
  func clustered(seed: UInt64) {
    runSimulation(seed: seed, config: Self.config(.clustered))
  }

  @Test(arguments: uniqueOwnerSeeds)
  func deep(seed: UInt64) {
    runSimulation(seed: seed, config: Self.config(.deep))
  }
}

#if canImport(Foundation)
/// Opt-in soak. Disabled unless `ART_SIM_STEPS` is set, so it never slows CI.
/// Example: `ART_SIM_STEPS=200000 ART_SIM_SEEDS=32 swift test --filter soak`
@Suite struct ARTreeSoakTests {
  static var isEnabled: Bool {
    ProcessInfo.processInfo.environment["ART_SIM_STEPS"] != nil
  }

  @Test(.enabled(if: isEnabled))
  func soak() {
    let env = ProcessInfo.processInfo.environment
    let steps = env["ART_SIM_STEPS"].flatMap { Int($0) } ?? 200_000
    let seedCount = env["ART_SIM_SEEDS"].flatMap { Int($0) } ?? 16
    for s in 0..<UInt64(seedCount) {
      for kind in [KeygenKind.clustered, .wide, .deep] {
        var cfg = SimulationConfig(keygenKind: kind)
        cfg.steps = steps
        runSimulation(seed: s &* 1009 &+ 1, config: cfg)
      }
    }
  }
}
#endif
