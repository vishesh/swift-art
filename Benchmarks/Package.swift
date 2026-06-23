// swift-tools-version:6.1
//===----------------------------------------------------------------------===//
//
// Benchmarks for swift-art. Kept in a separate package so the main library
// product stays dependency-free: swift-collections and the benchmark harness
// are only resolved when you build/run benchmarks from this directory.
//
//===----------------------------------------------------------------------===//

import PackageDescription

let package = Package(
  name: "swift-art-benchmarks",
  platforms: [
    // SortedCollections (prototype) carries recent availability; keep the
    // deployment target high. Benchmarks are a dev tool, not a shipped product.
    .macOS(.v15), .iOS(.v18), .watchOS(.v11), .tvOS(.v18),
  ],
  // Mirror swift-collections' own Benchmarks package: declare the trait, enable
  // it by default, and forward it to the swift-collections dependency. Gating
  // the SortedDictionary code in `#if UnstableSortedCollections` means the suite
  // still builds if the trait is ever turned off.
  traits: [
    .default(enabledTraits: ["UnstableSortedCollections"]),
    .trait(name: "UnstableSortedCollections"),
  ],
  dependencies: [
    .package(name: "swift-art", path: ".."),
    .package(
      url: "https://github.com/apple/swift-collections.git",
      from: "1.6.0",
      traits: [
        .trait(
          name: "UnstableSortedCollections",
          condition: .when(traits: ["UnstableSortedCollections"])),
      ]
    ),
    .package(
      url: "https://github.com/apple/swift-collections-benchmark",
      from: "0.0.4"),
  ],
  targets: [
    .executableTarget(
      name: "ARTBenchmarks",
      dependencies: [
        .product(name: "ARTreeModule", package: "swift-art"),
        .product(name: "HashTreeCollections", package: "swift-collections"),
        .product(name: "SortedCollections", package: "swift-collections"),
        .product(name: "CollectionsBenchmark", package: "swift-collections-benchmark"),
      ],
      path: "Sources/ARTBenchmarks"),
  ]
)
