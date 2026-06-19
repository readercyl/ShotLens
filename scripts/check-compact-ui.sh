#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MAIN_WINDOW="$ROOT_DIR/ShotLens/App/MainWindow.swift"
OVERLAY_WINDOW="$ROOT_DIR/ShotLens/Core/OverlayWindow.swift"
SELECT_WINDOW="$ROOT_DIR/ShotLens/Tools/ShotLensSelect.swift"

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
rg -n 'NSPanel' "$OVERLAY_WINDOW" "$SELECT_WINDOW" >/dev/null
rg -n 'nonactivatingPanel' "$OVERLAY_WINDOW" "$SELECT_WINDOW" >/dev/null
rg -n 'screenSaver' "$OVERLAY_WINDOW" "$SELECT_WINDOW" >/dev/null
rg -n '\.stationary' "$OVERLAY_WINDOW" "$SELECT_WINDOW" >/dev/null
rg -n 'containedRenderRect\(for: baseRect\)' "$OVERLAY_WINDOW" >/dev/null
rg -n 'var best = minimumSize' "$OVERLAY_WINDOW" >/dev/null

echo "Compact UI check passed."
