#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/tests"
TEST_BINARY="$BUILD_DIR/multi-display-capture-smoke"

mkdir -p "$BUILD_DIR"

swiftc \
  -parse-as-library \
  "$ROOT_DIR/ShotLens/Core/ShotLensLogger.swift" \
  "$ROOT_DIR/ShotLens/Core/ScreenshotCapture.swift" \
  "$ROOT_DIR/Tests/MultiDisplayCaptureSmoke.swift" \
  -o "$TEST_BINARY"

"$TEST_BINARY"
