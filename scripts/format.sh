#!/bin/sh
# Format all Swift sources in place using swift-format (bundled with the Swift 6
# toolchain — Xcode's `swift format` subcommand). Run from anywhere:
#
#   ./scripts/format.sh
#
set -eu
cd "$(dirname "$0")/.."
swift format --in-place --parallel --recursive Sources Tests Benchmarks/Sources
echo "Formatted Sources, Tests, Benchmarks/Sources."
