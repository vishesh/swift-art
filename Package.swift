// swift-tools-version:6.0
//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift ART open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

import PackageDescription

var defines: [String] = [
  "COLLECTIONS_RANDOMIZED_TESTING",
]

var _settings: [SwiftSetting] = defines.map { .define($0) }

let package = Package(
  name: "swift-art",
  platforms: [
    .macOS("15.0"), .iOS("16.4"), .watchOS("9.4"), .tvOS("16.4"),
  ],
  products: [
    .library(name: "ARTreeModule", targets: ["ARTreeModule"]),
    .executable(name: "Benchmarks", targets: ["Benchmarks"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-collections", from: "1.1.0"),
    .package(url: "https://github.com/apple/swift-collections-benchmark", from: "0.0.3"),
  ],
  targets: [
    // Test support library (shared assertion helpers, built on swift-testing).
    .target(
      name: "_CollectionsTestSupport",
      dependencies: [],
      path: "Tests/_CollectionsTestSupport",
      swiftSettings: _settings),

    // Adaptive Radix Tree source module.
    .target(
      name: "ARTreeModule",
      dependencies: [],
      path: "Sources/ARTreeModule",
      exclude: [
        "README.md",
      ],
      swiftSettings: _settings),

    // Adaptive Radix Tree tests.
    .testTarget(
      name: "ARTreeModuleTests",
      dependencies: ["ARTreeModule", "_CollectionsTestSupport"],
      path: "Tests/ARTreeModuleTests",
      swiftSettings: _settings),

    // Benchmark executable
    .executableTarget(
      name: "Benchmarks",
      dependencies: [
        "ARTreeModule",
        .product(name: "Collections", package: "swift-collections"),
        .product(name: "CollectionsBenchmark", package: "swift-collections-benchmark"),
      ],
      path: "Benchmarks",
      swiftSettings: _settings),
  ]
)
