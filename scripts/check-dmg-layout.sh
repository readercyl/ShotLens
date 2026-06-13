#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_PATH="${1:-$ROOT_DIR/build/release/dmg-staging}"

if [[ ! -d "$TARGET_PATH" ]]; then
  echo "DMG layout target is missing: $TARGET_PATH" >&2
  exit 1
fi

expected_items=$'Applications\nShotLens.app'
actual_items="$(find "$TARGET_PATH" -maxdepth 1 -mindepth 1 -exec basename {} \; | sort)"

if [[ "$actual_items" != "$expected_items" ]]; then
  echo "DMG must contain only ShotLens.app and Applications." >&2
  printf 'Actual top-level items:\n%s\n' "$actual_items" >&2
  exit 1
fi

test -d "$TARGET_PATH/ShotLens.app"
test -L "$TARGET_PATH/Applications"

echo "DMG layout check passed."
