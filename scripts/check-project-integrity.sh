#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
EXPECTED_BUNDLE_IDENTIFIER="com.qingcheng.shotlens.mac"

required_files=(
  "$ROOT_DIR/ShotLens/App/Info.plist"
  "$ROOT_DIR/ShotLens/Tools/ShotLensOCR.swift"
  "$ROOT_DIR/ShotLens/Core/InProcessSelectionOverlay.swift"
  "$ROOT_DIR/ShotLens/Core/LLMTranslator.swift"
  "$ROOT_DIR/ShotLens/Core/LLMConnectionChecker.swift"
  "$ROOT_DIR/ShotLens/Core/AppUpdater.swift"
  "$ROOT_DIR/Tests/TranslationEndpointSmoke.swift"
  "$ROOT_DIR/Tests/AppUpdaterSmoke.swift"
  "$ROOT_DIR/Tests/MultiDisplayCaptureSmoke.swift"
  "$ROOT_DIR/scripts/check-app-updater.sh"
  "$ROOT_DIR/scripts/check-multi-display-capture.sh"
  "$ROOT_DIR/scripts/check-compact-ui.sh"
  "$ROOT_DIR/scripts/ensure-local-signing-cert.sh"
  "$ROOT_DIR/scripts/check-release-signature.sh"
)

for file in "${required_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "Required project file is missing: $file" >&2
    exit 1
  fi
done

if git -C "$ROOT_DIR" ls-files | rg -q '(^|/)\.DS_Store$'; then
  echo "Remove tracked .DS_Store files before release." >&2
  exit 1
fi

if rg -n '^import Vision$' "$ROOT_DIR/ShotLens" --glob '*.swift' --glob '!**/Tools/**'; then
  echo "Main app sources must not import Vision; OCR belongs in the helper process." >&2
  exit 1
fi
rg -n '^import Vision$' "$ROOT_DIR/ShotLens/Tools/ShotLensOCR.swift" >/dev/null

rg -n 'ShotLens/Tools/ShotLensOCR.swift' "$ROOT_DIR/scripts/build-local.sh" >/dev/null
if rg -n 'ShotLensSelect|SelectionClient' "$ROOT_DIR/scripts/build-local.sh" "$ROOT_DIR/ShotLens/App" "$ROOT_DIR/ShotLens/Core" >/dev/null; then
  echo "Primary selection flow must not build or call the old ShotLensSelect helper." >&2
  exit 1
fi
rg -n 'LLMConnectionChecker.swift' "$ROOT_DIR/ShotLens.xcodeproj/project.pbxproj" >/dev/null
rg -n 'AppUpdater.swift' "$ROOT_DIR/ShotLens.xcodeproj/project.pbxproj" >/dev/null
rg -n 'InProcessSelectionOverlay.swift' "$ROOT_DIR/ShotLens.xcodeproj/project.pbxproj" >/dev/null
rg -n "<string>$EXPECTED_BUNDLE_IDENTIFIER</string>" "$ROOT_DIR/ShotLens/App/Info.plist" >/dev/null
rg -n "<string>$EXPECTED_BUNDLE_IDENTIFIER</string>" "$ROOT_DIR/scripts/build-local.sh" >/dev/null
test "$(rg -c "PRODUCT_BUNDLE_IDENTIFIER = $EXPECTED_BUNDLE_IDENTIFIER;" "$ROOT_DIR/ShotLens.xcodeproj/project.pbxproj")" -eq 2
rg -n 'migrateLegacyDefaultsIfNeeded' "$ROOT_DIR/ShotLens/App/ShotLensApp.swift" >/dev/null
rg -n 'chatCompletionsURL' "$ROOT_DIR/ShotLens/Core/LLMTranslator.swift" >/dev/null
rg -n 'LLMConnectionChecker' "$ROOT_DIR/ShotLens/App/MainWindow.swift" >/dev/null
rg -n 'AppUpdater' "$ROOT_DIR/ShotLens/App/MainWindow.swift" >/dev/null

while IFS= read -r script_name; do
  script_path="$ROOT_DIR/$script_name"
  if [[ ! -x "$script_path" ]]; then
    echo "README references a missing or non-executable script: $script_name" >&2
    exit 1
  fi
done < <(rg -o 'scripts/[A-Za-z0-9._-]+\.sh' "$ROOT_DIR/README.md" | cut -d: -f2 | sort -u)

echo "Project integrity check passed."
