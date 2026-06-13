#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT_DIR/ShotLens/App/ShotLensApp.swift"
CAPTURE="$ROOT_DIR/ShotLens/Core/ScreenshotCapture.swift"
OVERLAY="$ROOT_DIR/ShotLens/Core/OverlayWindow.swift"
MAIN="$ROOT_DIR/ShotLens/App/MainWindow.swift"
LOGGER="$ROOT_DIR/ShotLens/Core/ShotLensLogger.swift"
SELECT_HELPER="$ROOT_DIR/ShotLens/Tools/ShotLensSelect.swift"
LAYOUT="$ROOT_DIR/ShotLens/Core/TextLayoutOptimizer.swift"
TRANSLATOR="$ROOT_DIR/ShotLens/Core/LLMTranslator.swift"
SETTINGS="$ROOT_DIR/ShotLens/Core/TranslationSettings.swift"
PROVIDER="$ROOT_DIR/ShotLens/Core/TranslationProvider.swift"
BUILD_SCRIPT="$ROOT_DIR/scripts/build-local.sh"
DMG_SCRIPT="$ROOT_DIR/scripts/package-dmg.sh"
NEXT_VERSION_SCRIPT="$ROOT_DIR/scripts/next-release-version.sh"
PRIVATE_CONFIG_SCRIPT="$ROOT_DIR/scripts/check-no-private-config.sh"
DMG_LAYOUT_SCRIPT="$ROOT_DIR/scripts/check-dmg-layout.sh"

if [[ -e "$ROOT_DIR/ShotLens/Core/SelectionOverlay.swift" ]]; then
  echo "Old in-process SelectionOverlay must be removed; ShotLensSelect owns selection." >&2
  exit 1
fi
if [[ -e "$ROOT_DIR/ShotLens/Extensions/CGRect+Vision.swift" ]]; then
  echo "Old Vision CGRect extension must be removed; OCR helper owns Vision coordinate conversion." >&2
  exit 1
fi
if rg -n 'SelectionOverlay|CGRect\+Vision|E640D5BF74FBB8C9742B08E9|97EEAF52C4C8E59F914FF1CD' "$ROOT_DIR/ShotLens.xcodeproj/project.pbxproj"; then
  echo "Xcode project must not reference removed legacy files." >&2
  exit 1
fi

test -x "$NEXT_VERSION_SCRIPT"
test -x "$PRIVATE_CONFIG_SCRIPT"
test -x "$DMG_LAYOUT_SCRIPT"
rg -n 'APP_VERSION="\$\{SHOTLENS_APP_VERSION:-v1\.0\}"' "$BUILD_SCRIPT" >/dev/null
rg -n 'BUNDLE_SHORT_VERSION="\$\{APP_VERSION#v\}"' "$BUILD_SCRIPT" >/dev/null
rg -n 'APP_BUILD="\$\{SHOTLENS_APP_BUILD:-1\}"' "$BUILD_SCRIPT" >/dev/null
rg -n 'MIN_MACOS_VERSION="14\.0"' "$BUILD_SCRIPT" >/dev/null
rg -n '<string>\$BUNDLE_SHORT_VERSION</string>' "$BUILD_SCRIPT" >/dev/null
rg -n '<string>\$APP_BUILD</string>' "$BUILD_SCRIPT" >/dev/null
rg -n '<string>\$MIN_MACOS_VERSION</string>' "$BUILD_SCRIPT" >/dev/null
test -x "$DMG_SCRIPT"
rg -n 'next-release-version\.sh' "$DMG_SCRIPT" >/dev/null
rg -n 'hdiutil create' "$DMG_SCRIPT" >/dev/null
rg -n 'ShotLens-\$APP_VERSION\.dmg' "$DMG_SCRIPT" >/dev/null
rg -n 'check-no-private-config\.sh' "$DMG_SCRIPT" >/dev/null
rg -n 'check-dmg-layout\.sh' "$DMG_SCRIPT" >/dev/null
if rg -n '安装说明|right-click|右键|Apple-notarized|notarized|notarytool|stapler|SHOTLENS_NOTARY_PROFILE|Set SHOTLENS_CODESIGN_IDENTITY|spctl --assess' "$DMG_SCRIPT" "$ROOT_DIR/README.md" "$ROOT_DIR/scripts/release-github.sh"; then
  echo "Release flow must stay simple: no installer notes or Apple notarization/Gatekeeper instructions." >&2
  exit 1
fi

rg -n 'capture\(selection' "$CAPTURE" >/dev/null
rg -n 'hasScreenCaptureAccess\(\)' "$APP" >/dev/null
rg -n 'ScreenshotProcessResumeState' "$CAPTURE" >/dev/null
rg -n 'DispatchQueue\.global\(\)\.asyncAfter\(deadline: \.now\(\) \+ 15' "$CAPTURE" >/dev/null
rg -n 'captureFrozenDisplay\(\)' "$APP" "$CAPTURE" >/dev/null
rg -n 'select\(frozenScreenshot: frozenSnapshot\)' "$APP" >/dev/null
rg -n 'SelectionProcessResumeState' "$ROOT_DIR/ShotLens/Core/SelectionClient.swift" >/dev/null
rg -n 'DispatchQueue\.global\(\)\.asyncAfter\(deadline: \.now\(\) \+ 120' "$ROOT_DIR/ShotLens/Core/SelectionClient.swift" >/dev/null
rg -n 'crop\(frozenSnapshot: frozenSnapshot, selection: selection\)' "$APP" >/dev/null
rg -n 'struct FrozenScreenshot' "$CAPTURE" >/dev/null
if rg -n 'Task\.sleep\(nanoseconds: 100_000_000\)' "$APP"; then
  echo "Capture must freeze the screen before selection instead of waiting until after selection." >&2
  exit 1
fi
sed -n '/func applicationDidFinishLaunching/,/func applicationShouldTerminateAfterLastWindowClosed/p' "$APP" | rg -n 'openMainWindow\(' >/dev/null
rg -n 'ShotLens 控制台' "$MAIN" >/dev/null
rg -n 'clearAPISettingsClicked|resetSavedConfiguration|清空' "$MAIN" "$SETTINGS" >/dev/null
rg -n 'disableAutomaticTermination' "$APP" >/dev/null
rg -n 'makeMenuBarTemplateIcon\(\)' "$APP" >/dev/null
rg -n 'statusItem\(withLength: NSStatusItem\.squareLength\)' "$APP" >/dev/null
rg -n 'image\.isTemplate = true' "$APP" >/dev/null
rg -n 'button\.imagePosition = \.imageOnly' "$APP" >/dev/null
if rg -n 'button\.title = "义"|let text = "义"' "$APP"; then
  echo "Menu bar icon must use the 翻译的译 glyph, not 义." >&2
  exit 1
fi
ICON_GENERATOR="$ROOT_DIR/scripts/generate-shotlens-icons.swift"
rg -n 'drawAppIcon|drawMenuBarTemplateIcon|drawSimpleLogo' "$ICON_GENERATOR" >/dev/null
rg -n 'ShotLensMenuBarTemplate\.png' "$ROOT_DIR/scripts/build-local.sh" >/dev/null
if rg -n '0\.49|0\.83|0\.99|7dd3fc|0ea5e9|systemBlue|calibratedRed: 0\.[0-9]+, green: 0\.[0-9]+, blue: 0\.[5-9]' "$ICON_GENERATOR"; then
  echo "Selected B icon must use black background with white symbols only; no blue accent." >&2
  exit 1
fi
if sed -n '/private func handleHotKey/,/private func executeTranslationFlow/p' "$APP" | rg -n 'openMainWindow\('; then
  echo "Capture completion/cancel must not automatically reopen the main window." >&2
  exit 1
fi
if rg -n 'captureInteractive\(' "$APP" "$CAPTURE"; then
  echo "Workflow must not use native interactive screencapture; ShotLens owns the full-screen mask." >&2
  exit 1
fi

rg -n 'SelectionClient\(\)\.select' "$APP" >/dev/null
rg -n 'ShotLensSelect' "$ROOT_DIR/scripts/build-local.sh" >/dev/null
rg -n -- '--frozen-image' "$SELECT_HELPER" >/dev/null
rg -n 'backgroundImage' "$SELECT_HELPER" >/dev/null
rg -n 'cropForScreen' "$SELECT_HELPER" >/dev/null
if rg -n '拖拽选择要翻译的区域|Esc 取消|drawInstruction|drawSelectionSize' "$SELECT_HELPER"; then
  echo "Selection mask must be visual-only: no instruction text or size labels." >&2
  exit 1
fi
if rg -n 'context\.clear|clip\(\)' "$SELECT_HELPER"; then
  echo "Selection mask must avoid pixel-mask clearing paths that crash on this macOS build." >&2
  exit 1
fi

rg -n 'Task \{ \[weak self, weak overlay\]' "$APP" >/dev/null
rg -n 'OverlayStatusWindow|StatusContentView' "$OVERLAY" >/dev/null
rg -n 'setFailure\(message: message, retryTitle: "重新翻译"' "$OVERLAY" >/dev/null
rg -n 'StatusRetryButton' "$OVERLAY" >/dev/null
rg -n 'yBelow = anchorRect\.minY' "$OVERLAY" >/dev/null
rg -n 'onRetry' "$APP" "$OVERLAY" >/dev/null
rg -n 'OverlayBackdropWindow|OverlayBackdropView' "$OVERLAY" >/dev/null
rg -n 'addGlobalMonitorForEvents' "$OVERLAY" >/dev/null
rg -n 'let mouseLocation = NSEvent\.mouseLocation' "$OVERLAY" >/dev/null
rg -n 'resultWindow\.frame\.contains\(mouseLocation\)' "$OVERLAY" >/dev/null
rg -n 'statusWindow\?\.frame\.contains\(mouseLocation\)' "$OVERLAY" >/dev/null
if rg -n 'closeButton|onCloseTapped|onTranslateTapped|translateButton|copyButton|onCopyTapped|NSButton\(title: "X"|NSButton\(title: "翻译"|NSButton\(title: "复制"|✓|checkmark' "$OVERLAY" "$APP"; then
  echo "Result controls must not use the old checkmark save flow." >&2
  exit 1
fi
if rg -n 'NSAlert|showCaptureFailureAlert' "$APP"; then
  echo "Runtime errors must be logged internally instead of shown as blocking alerts." >&2
  exit 1
fi
rg -n 'ShotLensLogger\.log' "$APP" >/dev/null
rg -n 'Library/Logs/ShotLens' "$LOGGER" >/dev/null
rg -n 'TextLayoutOptimizer\.merge' "$APP" >/dev/null
rg -n 'enum TextLayoutOptimizer' "$LAYOUT" >/dev/null
rg -n 'lineBreakMode = \.byCharWrapping' "$OVERLAY" >/dev/null
rg -n 'textLayout\(for text' "$OVERLAY" >/dev/null
rg -n 'index<TAB>translation|lineProtocolEscaped|parseNumberedLines' "$TRANSLATOR" >/dev/null
rg -n 'isLLMConfigured' "$SETTINGS" "$PROVIDER" >/dev/null
rg -n 'API 翻译|所有翻译都走 API' "$MAIN" >/dev/null
if rg -n 'enum TranslationMode|defaultTranslationModeKey|case automatic|case system|case api|TranslationFallbackProvider|AppleSystemTranslator|TranslationSession|系统翻译|翻译方式|API 兜底' "$ROOT_DIR/ShotLens"; then
  echo "Translation must be API-only; old system translation modes must stay removed." >&2
  exit 1
fi
if rg -n 'GoogleTranslateFallback|translate\.googleapis\.com' "$PROVIDER" "$TRANSLATOR"; then
  echo "Translation fallback must use the configured API provider, not the unofficial Google endpoint." >&2
  exit 1
fi
rg -n 'literal translation|Do not polish|Do not rewrite' "$TRANSLATOR" >/dev/null

rg -n 'ShortcutRecorder\.hotKeyChangedNotification' "$MAIN" >/dev/null

echo "Workflow requirements check passed."
