#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/tests"
TEST_BINARY="$BUILD_DIR/overlay-geometry-smoke"

mkdir -p "$BUILD_DIR"

swiftc \
  "$ROOT_DIR/ShotLens/Models/TranslationResult.swift" \
  "$ROOT_DIR/ShotLens/Core/ClipboardManager.swift" \
  "$ROOT_DIR/ShotLens/Core/ShotLensLogger.swift" \
  "$ROOT_DIR/ShotLens/Core/OverlayControlVisibility.swift" \
  "$ROOT_DIR/ShotLens/Core/OverlayLayoutPlanner.swift" \
  "$ROOT_DIR/ShotLens/Core/OverlayWindow.swift" \
  "$ROOT_DIR/Tests/OverlayGeometrySmoke.swift" \
  -o "$TEST_BINARY"

"$TEST_BINARY"
