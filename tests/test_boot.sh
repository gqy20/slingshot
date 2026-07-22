#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BOOT_LOG="$(mktemp /tmp/slingshot-boot.XXXXXX.log)"

cleanup() {
  rm -f "$BOOT_LOG"
}
trap cleanup EXIT

xvfb-run -a timeout 20 godot --path "$PROJECT_ROOT" \
  --rendering-method gl_compatibility \
  -- --preset "$PROJECT_ROOT/presets/smoke.json" --boot-only \
  >"$BOOT_LOG" 2>&1

grep -Fq '[app] preset=smoke-shot' "$BOOT_LOG"
if grep -Eq 'SCRIPT ERROR|^ERROR:' "$BOOT_LOG"; then
  sed -n '1,200p' "$BOOT_LOG"
  exit 1
fi

printf 'BOOT TEST: passed\n'
