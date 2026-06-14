#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MAIN_WINDOW="$ROOT_DIR/ShotLens/App/MainWindow.swift"

rg -n 'apiDetailsExpandedKey' "$MAIN_WINDOW" >/dev/null
rg -n 'apiDetailsContainer' "$MAIN_WINDOW" >/dev/null
rg -n 'isApiDetailsExpanded = UserDefaults.standard.bool' "$MAIN_WINDOW" >/dev/null
rg -n 'toggleAPIExpandedClicked' "$MAIN_WINDOW" >/dev/null
rg -n 'updateWindowHeight' "$MAIN_WINDOW" >/dev/null
rg -n 'startUpdateButtonRotation' "$MAIN_WINDOW" >/dev/null
rg -n 'stopUpdateButtonRotation' "$MAIN_WINDOW" >/dev/null
rg -n 'CABasicAnimation' "$MAIN_WINDOW" >/dev/null

echo "Compact UI check passed."
