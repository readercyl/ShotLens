#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MAIN_WINDOW="$ROOT_DIR/ShotLens/App/MainWindow.swift"
TRANSLATION_SETTINGS="$ROOT_DIR/ShotLens/Core/TranslationSettings.swift"
OVERLAY_WINDOW="$ROOT_DIR/ShotLens/Core/OverlayWindow.swift"
SELECTION_OVERLAY="$ROOT_DIR/ShotLens/Core/InProcessSelectionOverlay.swift"
SCREENSHOT_CAPTURE="$ROOT_DIR/ShotLens/Core/ScreenshotCapture.swift"
SHOTLENS_APP="$ROOT_DIR/ShotLens/App/ShotLensApp.swift"

rg -n 'apiDetailsExpandedKey' "$MAIN_WINDOW" >/dev/null
rg -n 'apiDetailsContainer' "$MAIN_WINDOW" >/dev/null
rg -n 'isApiDetailsExpanded = UserDefaults.standard.bool' "$MAIN_WINDOW" >/dev/null
rg -n 'toggleAPIExpandedClicked' "$MAIN_WINDOW" >/dev/null
rg -n 'updateWindowHeight' "$MAIN_WINDOW" >/dev/null
rg -n 'checkUpdateButton.title = "检测新版本"' "$MAIN_WINDOW" >/dev/null
rg -n 'checkUpdateButton.title = "检测中…"' "$MAIN_WINDOW" >/dev/null
rg -n 'flushPendingSave\(\)' "$MAIN_WINDOW" >/dev/null
rg -n 'syncAPIKeyDraftFromField' "$MAIN_WINDOW" >/dev/null
rg -n 'NSButton\(title: "清空"' "$MAIN_WINDOW" >/dev/null
rg -n 'NSButton\(title: "恢复默认"' "$MAIN_WINDOW" >/dev/null
rg -n 'NSButton\(title: "测试"' "$MAIN_WINDOW" >/dev/null
rg -n 'apiDefaultNoteLabel' "$MAIN_WINDOW" >/dev/null
rg -n '默认限免' "$MAIN_WINDOW" >/dev/null
rg -n '异常消耗时可能随时停用，建议自备 Key' "$TRANSLATION_SETTINGS" >/dev/null

if rg -n 'showReleaseNotesIfNeeded|lastShownReleaseNotesVersionKey|更新完成' "$SHOTLENS_APP" >/dev/null; then
  echo "App launch must not show automatic release/update reminder popups." >&2
  exit 1
fi
if rg -n '截图翻译控制台' "$MAIN_WINDOW" >/dev/null; then
  echo "Main window should not repeat 截图翻译控制台 in the header." >&2
  exit 1
fi
if rg -n 'checkUpdateIconView|arrow.clockwise|CABasicAnimation|shotlens.update.spin' "$MAIN_WINDOW" >/dev/null; then
  echo "Update check should use a text button, not a spinning icon." >&2
  exit 1
fi
if rg -n 'minimumWidth|minimumHeight|singleLineWidth|containedRenderRect\(.*minimumSize|minimumSize: CGSize' "$OVERLAY_WINDOW" >/dev/null; then
  echo "Translation overlay should render inside the original OCR rect without expanding into nearby text." >&2
  exit 1
fi
if rg -n 'NSApp\.activate\(ignoringOtherApps: true\)' "$OVERLAY_WINDOW" >/dev/null; then
  echo "Result overlay must not activate the main app because activation can switch away from fullscreen Spaces." >&2
  exit 1
fi
rg -n 'NSPanel' "$OVERLAY_WINDOW" "$SELECTION_OVERLAY" >/dev/null
rg -n 'nonactivatingPanel' "$OVERLAY_WINDOW" "$SELECTION_OVERLAY" >/dev/null
rg -n 'screenSaver' "$OVERLAY_WINDOW" "$SELECTION_OVERLAY" >/dev/null
rg -n '\.stationary' "$OVERLAY_WINDOW" "$SELECTION_OVERLAY" >/dev/null
rg -n 'override func acceptsFirstMouse' "$SELECTION_OVERLAY" >/dev/null
if rg -n 'for screen in screens' "$SELECTION_OVERLAY" >/dev/null; then
  echo "Selection overlay must only cover the screen under the mouse." >&2
  exit 1
fi
rg -n 'import ScreenCaptureKit' "$SCREENSHOT_CAPTURE" >/dev/null
rg -n 'SCScreenshotManager' "$SCREENSHOT_CAPTURE" >/dev/null
if rg -n '/usr/sbin/screencapture|CGWindowListCreateImage|CGDisplayCreateImage|process\.executableURL|process\.run\(\)' "$SCREENSHOT_CAPTURE" >/dev/null; then
  echo "Primary screenshot capture must stay in-process; external screencapture causes visible Space/window refresh." >&2
  exit 1
fi
if rg -n 'SelectionClient\(\)\.select|ShotLensSelect' "$SHOTLENS_APP" "$ROOT_DIR/ShotLens/Core" "$ROOT_DIR/scripts/build-local.sh" >/dev/null; then
  echo "Primary selection flow must stay in-process; cold-launching ShotLensSelect can cause a visible flash." >&2
  exit 1
fi
rg -n 'InProcessSelectionOverlay' "$SHOTLENS_APP" "$SELECTION_OVERLAY" >/dev/null
rg -n 'containedRenderRect\(for: baseRect\)' "$OVERLAY_WINDOW" >/dev/null
rg -n 'var best = minimumSize' "$OVERLAY_WINDOW" >/dev/null

echo "Compact UI check passed."
