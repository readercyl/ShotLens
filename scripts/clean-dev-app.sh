#!/usr/bin/env bash
set -euo pipefail

# 删掉本机开发版 App，让发版后 Spotlight 里只剩 /Applications 的正式版。
# 下一轮开发重新跑 scripts/build-local.sh 即可生成，Bundle ID 与签名证书不变，
# 屏幕录制、钥匙串等已有授权会继续有效。

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEV_APP="$ROOT_DIR/build/local/ShotLens 开发版.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [[ ! -d "$DEV_APP" ]]; then
  echo "No local development app to remove."
  exit 0
fi

if pgrep -f "$DEV_APP/Contents/MacOS/ShotLens" >/dev/null 2>&1; then
  echo "Development app is running; quit it before removing: $DEV_APP" >&2
  exit 1
fi

if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -u "$DEV_APP" >/dev/null 2>&1 || true
fi
rm -rf "$DEV_APP"

echo "Removed $DEV_APP"
