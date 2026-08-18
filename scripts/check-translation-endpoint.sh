#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/tests"
TEST_BINARY="$BUILD_DIR/translation-endpoint-smoke"

mkdir -p "$BUILD_DIR"

swiftc \
  "$ROOT_DIR/ShotLens/Core/TranslationSettings.swift" \
  "$ROOT_DIR/ShotLens/Core/TranslationProvider.swift" \
  "$ROOT_DIR/ShotLens/Core/ShotLensLogger.swift" \
  "$ROOT_DIR/ShotLens/Core/LLMTranslator.swift" \
  "$ROOT_DIR/ShotLens/Core/LLMConnectionChecker.swift" \
  "$ROOT_DIR/Tests/TranslationEndpointSmoke.swift" \
  -o "$TEST_BINARY"

"$TEST_BINARY"

rg -n 'request\.timeoutInterval = 30' "$ROOT_DIR/ShotLens/Core/LLMTranslator.swift" >/dev/null
rg -n 'payload\["thinking"\] = \["type": "disabled"\]' "$ROOT_DIR/ShotLens/Core/LLMTranslator.swift" >/dev/null
rg -n 'parseIndexedLineSlots' "$ROOT_DIR/ShotLens/Core/LLMTranslator.swift" >/dev/null
