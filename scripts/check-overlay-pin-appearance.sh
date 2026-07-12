#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/tests"
TEST_BINARY="$BUILD_DIR/overlay-pin-appearance-smoke"
mkdir -p "$BUILD_DIR"

swiftc \
  "$ROOT_DIR/ShotLens/Core/OverlayPinAppearance.swift" \
  "$ROOT_DIR/Tests/OverlayPinAppearanceSmoke.swift" \
  -o "$TEST_BINARY"

"$TEST_BINARY"
