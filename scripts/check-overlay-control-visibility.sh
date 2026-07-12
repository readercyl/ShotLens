#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/tests"
TEST_BINARY="$BUILD_DIR/overlay-control-visibility-smoke"

mkdir -p "$BUILD_DIR"
swiftc \
  "$ROOT_DIR/ShotLens/Core/OverlayControlVisibility.swift" \
  "$ROOT_DIR/Tests/OverlayControlVisibilitySmoke.swift" \
  -o "$TEST_BINARY"
"$TEST_BINARY"
