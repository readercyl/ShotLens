#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/tests"
TEST_BINARY="$BUILD_DIR/text-layout-optimizer-smoke"

mkdir -p "$BUILD_DIR"

swiftc \
  "$ROOT_DIR/ShotLens/Models/TranslationResult.swift" \
  "$ROOT_DIR/ShotLens/Core/TextLayoutOptimizer.swift" \
  "$ROOT_DIR/Tests/TextLayoutOptimizerSmoke.swift" \
  -o "$TEST_BINARY"

"$TEST_BINARY"

rg -n -F 'let sourceLang = "en"' "$ROOT_DIR/ShotLens/App/ShotLensApp.swift" >/dev/null
rg -n -F 'let targetLang = "zh-Hans"' "$ROOT_DIR/ShotLens/App/ShotLensApp.swift" >/dev/null
rg -n -F 'request.recognitionLanguages = ["en-US"]' "$ROOT_DIR/ShotLens/Tools/ShotLensOCR.swift" >/dev/null
