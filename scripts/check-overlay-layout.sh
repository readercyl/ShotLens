#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/tests"
TEST_BINARY="$BUILD_DIR/overlay-layout-smoke"
mkdir -p "$BUILD_DIR"
swiftc \
  "$ROOT_DIR/ShotLens/Core/OverlayLayoutPlanner.swift" \
  "$ROOT_DIR/Tests/OverlayLayoutSmoke.swift" \
  -o "$TEST_BINARY"
"$TEST_BINARY"
