#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/matter-metal-checks.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
xcrun -sdk macosx metal -c -I "$project_root/view" "$project_root/view/Shaders.metal" -o "$check_dir/Shaders.air"
xcrun -sdk macosx metallib "$check_dir/Shaders.air" -o "$check_dir/default.metallib"
xcrun -sdk macosx swiftc -O -import-objc-header "$project_root/view/view-Bridging-Header.h" \
  "$project_root/Tests/MetalEngineChecks.swift" -o "$check_dir/MetalEngineChecks"
"$check_dir/MetalEngineChecks" "$check_dir/default.metallib"
