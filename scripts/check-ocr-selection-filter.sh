#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/tests"
OCR_HELPER="$BUILD_DIR/shotlens-ocr-selection-filter-helper"
TEST_BINARY="$BUILD_DIR/ocr-selection-filter-smoke"

mkdir -p "$BUILD_DIR"

swiftc \
  -O \
  -target arm64-apple-macosx14.0 \
  -parse-as-library \
  "$ROOT_DIR/ShotLens/Tools/ShotLensOCR.swift" \
  -o "$OCR_HELPER"

swiftc \
  -target arm64-apple-macosx14.0 \
  -parse-as-library \
  "$ROOT_DIR/Tests/OCRSelectionFilterSmoke.swift" \
  -o "$TEST_BINARY"

"$TEST_BINARY" "$OCR_HELPER"

swiftc -D SHOTLENS_OCR_TESTS -parse-as-library \
  "$ROOT_DIR/ShotLens/Tools/ShotLensOCR.swift" \
  "$ROOT_DIR/Tests/OCRPostProcessingSmoke.swift" \
  -o "$BUILD_DIR/ocr-post-processing-smoke"
"$BUILD_DIR/ocr-post-processing-smoke"

rg -n 'let originalBlocks = try recognizeTextBlocks' "$ROOT_DIR/ShotLens/Tools/ShotLensOCR.swift" >/dev/null
rg -n 'mergeRecognitionPasses\(primary: originalBlocks, supplemental: enhancedBlocks\)' "$ROOT_DIR/ShotLens/Tools/ShotLensOCR.swift" >/dev/null
rg -n 'shouldRunEnhancedPass\(primary: originalBlocks, image: image\)' "$ROOT_DIR/ShotLens/Tools/ShotLensOCR.swift" >/dev/null
rg -n 'request\.usesLanguageCorrection = !fast' "$ROOT_DIR/ShotLens/Tools/ShotLensOCR.swift" >/dev/null
rg -n 'request\.automaticallyDetectsLanguage = true' "$ROOT_DIR/ShotLens/Tools/ShotLensOCR.swift" >/dev/null
rg -n 'supportedRecognitionLanguages\(for: request\)' "$ROOT_DIR/ShotLens/Tools/ShotLensOCR.swift" >/dev/null
rg -n 'request\.supportedRecognitionLanguages\(\)' "$ROOT_DIR/ShotLens/Tools/ShotLensOCR.swift" >/dev/null
rg -n 'allow-edge-text' "$ROOT_DIR/ShotLens/Core/OCREngine.swift" "$ROOT_DIR/ShotLens/Tools/ShotLensOCR.swift" >/dev/null
rg -n 'boundingBox\(for:' "$ROOT_DIR/ShotLens/Tools/ShotLensOCR.swift" >/dev/null
