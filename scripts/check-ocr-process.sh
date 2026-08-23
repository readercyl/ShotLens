#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/tests/ocr-process"
TEST_BINARY="$BUILD_DIR/ocr-process-smoke"
HELPER_BINARY="$BUILD_DIR/ShotLensOCR"

mkdir -p "$BUILD_DIR"

SOURCES=(
  "$ROOT_DIR/ShotLens/Models/TranslationResult.swift"
  "$ROOT_DIR/ShotLens/Core/TranslationPipelineState.swift"
  "$ROOT_DIR/ShotLens/Core/ShotLensLogger.swift"
  "$ROOT_DIR/ShotLens/Core/OCREngine.swift"
  "$ROOT_DIR/Tests/OCRProcessSmoke.swift"
)

swiftc -target arm64-apple-macosx14.0 "${SOURCES[@]}" -o "$TEST_BINARY"
swiftc -target arm64-apple-macosx14.0 "${SOURCES[@]}" -o "$HELPER_BINARY"

"$TEST_BINARY"
