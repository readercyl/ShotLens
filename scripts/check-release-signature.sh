#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="${1:-$ROOT_DIR/build/release/dmg-staging/ShotLens.app}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle is missing: $APP_PATH" >&2
  exit 1
fi

declared_macos_version="$(plutil -extract LSMinimumSystemVersion raw "$APP_PATH/Contents/Info.plist")"
for executable in "$APP_PATH/Contents/MacOS/ShotLens" "$APP_PATH/Contents/MacOS/ShotLensOCR"; do
  actual_macos_version="$(otool -l "$executable" | awk '/LC_BUILD_VERSION/{found=1; next} found && $1=="minos" {print $2; exit}')"
  if [[ "$actual_macos_version" != "$declared_macos_version" ]]; then
    echo "$(basename "$executable") requires macOS $actual_macos_version, but Info.plist declares $declared_macos_version." >&2
    exit 1
  fi
done

signature_info="$(codesign -dv --verbose=4 "$APP_PATH" 2>&1 || true)"

if rg -q 'Signature=adhoc' <<<"$signature_info"; then
  echo "Release app must not be ad-hoc signed; screen recording permission will reset across updates." >&2
  exit 1
fi

requirement="$(codesign -dr - "$APP_PATH" 2>&1 || true)"
if rg -q '^designated => cdhash ' <<<"$requirement"; then
  echo "Release app designated requirement must not be cdhash-only; use a stable signing certificate." >&2
  exit 1
fi

if ! rg -q 'identifier "com\.qingcheng\.shotlens\.mac"' <<<"$requirement"; then
  echo "Release app designated requirement must include the stable ShotLens bundle identifier." >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH" >/dev/null

echo "Release signature check passed."
