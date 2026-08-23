#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/tests"
TEST_BINARY="$BUILD_DIR/multi-display-capture-smoke"

mkdir -p "$BUILD_DIR"

swiftc \
  -parse-as-library \
  "$ROOT_DIR/ShotLens/Core/ShotLensLogger.swift" \
  "$ROOT_DIR/ShotLens/Models/TranslationResult.swift" \
  "$ROOT_DIR/ShotLens/Core/ScreenshotCapture.swift" \
  "$ROOT_DIR/Tests/MultiDisplayCaptureSmoke.swift" \
  -o "$TEST_BINARY"

"$TEST_BINARY"

rg -n '保留内存图像' "$ROOT_DIR/ShotLens/Core/ScreenshotCapture.swift" >/dev/null
if sed -n '/struct FrozenScreenshot {/,/^}/p' "$ROOT_DIR/ShotLens/Core/ScreenshotCapture.swift" | rg 'fileURL' >/dev/null; then
  echo "Frozen full-screen captures must not be encoded to an unused temporary PNG." >&2
  exit 1
fi
