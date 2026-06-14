#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="${2:-$ROOT_DIR/build/local/ShotLens.app}"
DMG_PATH="${1:-$ROOT_DIR/build/release/ShotLens-$("$ROOT_DIR/scripts/next-release-version.sh").dmg}"
DEFAULTS_DOMAIN="com.qingcheng.shotlens"
PUBLIC_DEFAULT_API_ENDPOINT="https://api.siliconflow.cn/v1"
PUBLIC_DEFAULT_API_KEY="sk-iiwyxcrwfaiqixpbfitsogijhfjsiolqtntqszuixgohjpnb"

read_default() {
  defaults read "$DEFAULTS_DOMAIN" "$1" 2>/dev/null || true
}

check_literal_absent() {
  local label="$1"
  local value="$2"
  shift 2

  [[ -n "$value" ]] || return 0
  if [[ "$value" == "$PUBLIC_DEFAULT_API_ENDPOINT" || "$value" == "$PUBLIC_DEFAULT_API_KEY" ]]; then
    return 0
  fi

  for path in "$@"; do
    [[ -e "$path" ]] || continue
    if rg -a -q --fixed-strings -- "$value" "$path"; then
      echo "Private API setting leaked into a release artifact: $label" >&2
      exit 1
    fi
  done
}

check_secret_pattern_absent() {
  local path="$1"

  [[ -e "$path" ]] || return 0

  while IFS= read -r match; do
    [[ -n "$match" ]] || continue
    if [[ "$match" != "$PUBLIC_DEFAULT_API_KEY" ]]; then
      echo "A possible API key pattern was found in a release artifact." >&2
      exit 1
    fi
  done < <(rg -a -o --no-filename 'sk-[A-Za-z0-9_-]{20,}' "$path" 2>/dev/null || true)
}

api_endpoint="$(read_default ShotLens_LLM_APIEndpoint)"
api_key="$(read_default ShotLens_LLM_APIKey)"

source_paths=(
  "$ROOT_DIR/README.md"
  "$ROOT_DIR/ShotLens"
  "$ROOT_DIR/ShotLens.xcodeproj"
  "$ROOT_DIR/Tests"
  "$ROOT_DIR/scripts"
)

artifact_paths=(
  "$APP_BUNDLE"
  "$ROOT_DIR/build/release/dmg-staging/ShotLens.app"
)

check_literal_absent "API endpoint" "$api_endpoint" "${source_paths[@]}" "${artifact_paths[@]}"
check_literal_absent "API key" "$api_key" "${source_paths[@]}" "${artifact_paths[@]}"

for path in "${source_paths[@]}" "${artifact_paths[@]}"; do
  check_secret_pattern_absent "$path"
done

if [[ -f "$DMG_PATH" ]]; then
  mount_dir="$(mktemp -d)"
  cleanup() {
    hdiutil detach "$mount_dir" -quiet 2>/dev/null || true
    rmdir "$mount_dir" 2>/dev/null || true
  }
  trap cleanup EXIT

  hdiutil attach "$DMG_PATH" -nobrowse -readonly -mountpoint "$mount_dir" >/dev/null
  check_literal_absent "API endpoint" "$api_endpoint" "$mount_dir"
  check_literal_absent "API key" "$api_key" "$mount_dir"
  check_secret_pattern_absent "$mount_dir"
fi

echo "Private API config check passed."
