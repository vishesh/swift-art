#!/bin/sh
# Check formatting without modifying files (exits non-zero on any violation).
#
#   ./scripts/lint.sh
#
set -eu
cd "$(dirname "$0")/.."
swift format lint --strict --parallel --recursive Sources Tests Benchmarks/Sources
