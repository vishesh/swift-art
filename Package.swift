// swift-tools-version:5.6
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
  products: [
    .library(name: "ARTreeModule", targets: ["ARTreeModule"]),
  ],
  targets: [
    // Test support library (not a test target — links XCTest explicitly).
    // unsafeFlags provides XCTest framework + Swift overlay search paths for
    // command-line builds, where SPM doesn't add them for regular targets.
    .target(
      name: "_CollectionsTestSupport",
      dependencies: [],
      path: "Tests/_CollectionsTestSupport",
      swiftSettings: _settings + [
        .unsafeFlags(
          ["-F",
           "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks",
           "-I",
           "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib"],
          .when(platforms: [.macOS])),
      ],
      linkerSettings: [
        .linkedFramework("XCTest", .when(platforms: [.macOS, .iOS, .watchOS, .tvOS])),
      ]),

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
  ]
)
