#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MAIN_WINDOW="$ROOT_DIR/ShotLens/App/MainWindow.swift"

rg -n 'apiDetailsExpandedKey' "$MAIN_WINDOW" >/dev/null
rg -n 'apiDetailsContainer' "$MAIN_WINDOW" >/dev/null
rg -n 'isApiDetailsExpanded = UserDefaults.standard.bool' "$MAIN_WINDOW" >/dev/null
rg -n 'toggleAPIExpandedClicked' "$MAIN_WINDOW" >/dev/null
rg -n 'updateWindowHeight' "$MAIN_WINDOW" >/dev/null
rg -n 'checkUpdateButton.title = "测试新版"' "$MAIN_WINDOW" >/dev/null
rg -n 'checkUpdateButton.title = "测试中…"' "$MAIN_WINDOW" >/dev/null
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

echo "Compact UI check passed."
