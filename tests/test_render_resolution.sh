#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/.." && pwd)"
resolution_tmp="$(mktemp -d /tmp/slingshot-resolution-test.XXXXXX)"
cleanup() {
  find "$resolution_tmp" -depth -delete
}
trap cleanup EXIT

EPISODE_RENDER_WIDTH=1920 \
EPISODE_RENDER_HEIGHT=1080 \
EPISODE_RENDER_WORKERS=1 \
EPISODE_SKIP_NARRATION=1 \
  "$PROJECT_ROOT/scripts/render_episode.sh" \
  "$PROJECT_ROOT/content/episodes/smoke.json" \
  "$resolution_tmp/smoke-1080p.mp4" >/dev/null

probe="$(
  ffprobe -v error -select_streams v:0 \
    -show_entries stream=width,height -of csv=p=0:s=x \
    "$resolution_tmp/smoke-1080p.mp4"
)"
if [[ "$probe" != 1920x1080 ]]; then
  printf 'render resolution test expected 1920x1080, got %s\n' "$probe" >&2
  exit 1
fi

if ! grep -Fq 'render_resolution=1920x1080' \
  "$resolution_tmp/smoke-1080p.manifest.txt"; then
  printf 'render resolution manifest does not record true 1080p output\n' >&2
  exit 1
fi

printf 'RENDER RESOLUTION TEST: passed\n'
