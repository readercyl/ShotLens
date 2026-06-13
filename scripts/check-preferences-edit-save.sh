#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MAIN_WINDOW="$ROOT_DIR/ShotLens/App/MainWindow.swift"
SETTINGS="$ROOT_DIR/ShotLens/Core/TranslationSettings.swift"
PROVIDER="$ROOT_DIR/ShotLens/Core/TranslationProvider.swift"

rg -n 'ShotLens 控制台' "$MAIN_WINDOW" >/dev/null
rg -n '屏幕录制权限' "$MAIN_WINDOW" >/dev/null
rg -n 'ShortcutRecorder' "$MAIN_WINDOW" >/dev/null
rg -n 'API 翻译' "$MAIN_WINDOW" >/dev/null
rg -n '设置会自动保存' "$MAIN_WINDOW" >/dev/null
rg -n '所有翻译都走 API' "$MAIN_WINDOW" >/dev/null
rg -n 'clearAPISettingsClicked|清空' "$MAIN_WINDOW" >/dev/null
rg -n 'resetSavedConfiguration' "$SETTINGS" >/dev/null
rg -n 'apiAvailabilityText' "$SETTINGS" >/dev/null
rg -n 'isLLMConfigured' "$SETTINGS" "$PROVIDER" >/dev/null
rg -n 'TranslationSettings\.didChangeNotification' "$MAIN_WINDOW" >/dev/null
rg -n 'ShortcutRecorder\.hotKeyChangedNotification' "$MAIN_WINDOW" >/dev/null

if rg -n 'PreferencesWindow|translationModeControl|默认翻译方式|翻译方式|系统翻译|API 兜底|TranslationMode|defaultTranslationMode|AppleSystemTranslator' "$ROOT_DIR/ShotLens"; then
  echo "Control console must stay API-only and must not expose the old preferences/system-translation UI." >&2
  exit 1
fi

echo "Control console edit/save check passed."
