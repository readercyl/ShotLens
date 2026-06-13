#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT_DIR/ShotLens/App/ShotLensApp.swift"
MAIN="$ROOT_DIR/ShotLens/App/MainWindow.swift"
ICON_GENERATOR="$ROOT_DIR/scripts/generate-shotlens-icons.swift"
BUILD_SCRIPT="$ROOT_DIR/scripts/build-local.sh"
DMG_SCRIPT="$ROOT_DIR/scripts/package-dmg.sh"
NEXT_VERSION_SCRIPT="$ROOT_DIR/scripts/next-release-version.sh"
PRIVATE_CONFIG_SCRIPT="$ROOT_DIR/scripts/check-no-private-config.sh"
DMG_LAYOUT_SCRIPT="$ROOT_DIR/scripts/check-dmg-layout.sh"
GITHUB_RELEASE_SCRIPT="$ROOT_DIR/scripts/release-github.sh"
README="$ROOT_DIR/README.md"
PROJECT="$ROOT_DIR/ShotLens.xcodeproj/project.pbxproj"

test -x "$NEXT_VERSION_SCRIPT"
test -x "$PRIVATE_CONFIG_SCRIPT"
test -x "$DMG_LAYOUT_SCRIPT"
test -x "$GITHUB_RELEASE_SCRIPT"

rg -n 'APP_VERSION="\$\{SHOTLENS_APP_VERSION:-v1\.0\}"' "$BUILD_SCRIPT" >/dev/null
rg -n 'BUNDLE_SHORT_VERSION="\$\{APP_VERSION#v\}"' "$BUILD_SCRIPT" >/dev/null
rg -n 'APP_BUILD="\$\{SHOTLENS_APP_BUILD:-1\}"' "$BUILD_SCRIPT" >/dev/null
rg -n 'DEPLOY_DIR="\$\{SHOTLENS_DEPLOY_DIR:-\$BUILD_DIR\}"' "$BUILD_SCRIPT" >/dev/null
rg -n '<string>\$BUNDLE_SHORT_VERSION</string>' "$BUILD_SCRIPT" >/dev/null

rg -n 'APP_VERSION="\$\{SHOTLENS_APP_VERSION:-\$\("\$ROOT_DIR/scripts/next-release-version\.sh"\)\}"' "$DMG_SCRIPT" >/dev/null
rg -n 'ShotLens-\$APP_VERSION\.dmg' "$DMG_SCRIPT" >/dev/null
rg -n 'SHOTLENS_CODESIGN_IDENTITY:-' "$DMG_SCRIPT" >/dev/null
rg -n 'SHOTLENS_APP_VERSION="\$APP_VERSION"' "$DMG_SCRIPT" >/dev/null
rg -n 'codesign --verify --deep --strict' "$DMG_SCRIPT" >/dev/null
rg -n 'hdiutil verify' "$DMG_SCRIPT" >/dev/null
rg -n 'check-no-private-config\.sh' "$DMG_SCRIPT" "$README" >/dev/null
rg -n 'check-dmg-layout\.sh' "$DMG_SCRIPT" "$README" >/dev/null
if rg -n '安装说明|right-click|右键|Apple-notarized|notarized|notarytool|stapler|SHOTLENS_NOTARY_PROFILE|Set SHOTLENS_CODESIGN_IDENTITY|spctl --assess' "$DMG_SCRIPT" "$README" "$GITHUB_RELEASE_SCRIPT"; then
  echo "Release packaging must stay simple: no installer notes, notarization instructions, or Gatekeeper assessment step." >&2
  exit 1
fi
if rg -n '安装说明|\\.txt' "$DMG_SCRIPT"; then
  echo "DMG must not include installer text files." >&2
  exit 1
fi
if rg -n 'notarytool|stapler|SHOTLENS_NOTARY_PROFILE|Set SHOTLENS_CODESIGN_IDENTITY' "$DMG_SCRIPT" "$README"; then
  echo "Friend-share packaging must not require Apple notarization or a Developer ID identity." >&2
  exit 1
fi
rg -n 'next-release-version\.sh|release-github\.sh|SHOTLENS_APP_VERSION' "$README" >/dev/null
rg -n 'ShotLens-\$VERSION\.dmg' "$README" >/dev/null
if rg -n 'ShotLens-V1\.0\.dmg|ShotLens-1\.0\.dmg' "$README" "$BUILD_SCRIPT" "$DMG_SCRIPT"; then
  echo "Release docs and scripts must use lowercase-v release naming." >&2
  exit 1
fi
if rg -n 'APP_VERSION="v1\.0"' "$BUILD_SCRIPT" "$DMG_SCRIPT"; then
  echo "Release scripts must derive the release version instead of hardcoding v1.0." >&2
  exit 1
fi

rg -n 'displayVersion' "$MAIN" "$APP" >/dev/null
rg -n '版本 \\\(displayVersion\)|versionLabel|版本 v1\.0' "$MAIN" >/dev/null

rg -n 'import ServiceManagement' "$MAIN" "$APP" >/dev/null
rg -n 'SMAppService\.mainApp' "$MAIN" "$APP" >/dev/null
rg -n '开机自动启动' "$MAIN" >/dev/null
rg -n 'launchAtLogin' "$MAIN" "$APP" >/dev/null
rg -n 'resetSavedConfiguration|clearAPISettingsClicked|清空' "$MAIN" "$ROOT_DIR/ShotLens/Core/TranslationSettings.swift" >/dev/null

rg -n 'statusItem\(withLength: NSStatusItem\.squareLength\)' "$APP" >/dev/null
rg -n 'let text = "译"' "$APP" "$MAIN" "$ICON_GENERATOR" >/dev/null
if rg -n 'let text = "义"' "$APP" "$MAIN" "$ICON_GENERATOR"; then
  echo "The app and menu bar glyph must use 译, not 义." >&2
  exit 1
fi

for project_file in \
  MainWindow.swift \
  LLMTranslator.swift \
  SelectionClient.swift \
  ShotLensLanguage.swift \
  ShotLensLogger.swift \
  TextLayoutOptimizer.swift \
  TranslationSettings.swift \
  ShotLens.icns \
  ShotLensMenuBarTemplate.png
do
  rg -n "$project_file" "$PROJECT" >/dev/null
done
rg -n 'Resources \*/ = \{' "$PROJECT" >/dev/null
rg -n 'PBXResourcesBuildPhase' "$PROJECT" >/dev/null

echo "Release requirements check passed."
