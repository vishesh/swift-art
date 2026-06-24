#!/bin/sh
# Profile a RadixTree workload and open the result in Instruments.
#
#   ./scripts/profile.sh <build|lookup|iterate|delete> [cpu|alloc] [n] [seconds]
#
# Examples:
#   ./scripts/profile.sh lookup            # CPU time profile of 1M-key lookups
#   ./scripts/profile.sh build alloc       # allocation profile of build
#
# Requires Xcode (provides `xctrace`). For an interactive in-browser flame graph,
# see the "Profiling" section of Benchmarks/README.md (samply).
set -eu

op="${1:?usage: profile.sh <build|lookup|iterate|delete> [cpu|alloc] [n] [seconds]}"
mode="${2:-cpu}"
n="${3:-1000000}"
secs="${4:-12}"

cd "$(dirname "$0")/../Benchmarks"
swift build -c release
bin="$PWD/.build/release/ARTBenchmarks"

case "$mode" in
  cpu) template="Time Profiler" ;;
  alloc) template="Allocations" ;;
  *) echo "mode must be 'cpu' or 'alloc'"; exit 1 ;;
esac

out="profile-$op-$mode.trace"
rm -rf "$out"
xctrace record --template "$template" --output "$out" --launch -- \
  "$bin" profile "$op" "$n" "$secs"
echo "Recorded $out"
open "$out"
