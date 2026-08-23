#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/tests"
TEST_BINARY="$BUILD_DIR/pipeline-diagnostics-smoke"

mkdir -p "$BUILD_DIR"
swiftc \
  "$ROOT_DIR/ShotLens/Core/TranslationPipelineState.swift" \
  "$ROOT_DIR/ShotLens/Core/ShotLensLogger.swift" \
  "$ROOT_DIR/Tests/PipelineDiagnosticsSmoke.swift" \
  -o "$TEST_BINARY"

"$TEST_BINARY"
