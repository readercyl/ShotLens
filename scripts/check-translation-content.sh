#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/tests"
TEST_BINARY="$BUILD_DIR/translation-content-planner-smoke"

mkdir -p "$BUILD_DIR"

swiftc \
  "$ROOT_DIR/ShotLens/Models/TranslationResult.swift" \
  "$ROOT_DIR/ShotLens/Core/TranslationContentPlanner.swift" \
  "$ROOT_DIR/Tests/TranslationContentPlannerSmoke.swift" \
  -o "$TEST_BINARY"

"$TEST_BINARY"

rg -n 'provider\.translateAvailable' "$ROOT_DIR/ShotLens/App/ShotLensApp.swift" >/dev/null
rg -n 'contentPlan\.applyingAvailable' "$ROOT_DIR/ShotLens/App/ShotLensApp.swift" >/dev/null
rg -n '重新翻译：从现有框选截图重新执行 OCR 和翻译' "$ROOT_DIR/ShotLens/App/ShotLensApp.swift" >/dev/null
rg -n 'SemanticTextGrouper\.merge' "$ROOT_DIR/ShotLens/App/ShotLensApp.swift" >/dev/null
if rg -n 'TextLayoutOptimizer|TextLayoutKind' "$ROOT_DIR/ShotLens/App/ShotLensApp.swift" "$ROOT_DIR/ShotLens/Core/TranslationContentPlanner.swift" >/dev/null; then
  echo "Translation flow must use geometry-only semantic grouping without page-type classification." >&2
  exit 1
fi
