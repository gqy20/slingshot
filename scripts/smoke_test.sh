#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SMOKE_DIR="$(mktemp -d /tmp/slingshot-render-smoke.XXXXXX)"

cleanup() {
  rm -rf "$SMOKE_DIR"
}
trap cleanup EXIT

OUTPUT_MP4="$SMOKE_DIR/smoke.mp4"
"$SCRIPT_DIR/render.sh" "$PROJECT_ROOT/presets/smoke.json" "$OUTPUT_MP4"

test -s "$OUTPUT_MP4"
test -s "${OUTPUT_MP4%.mp4}.json"

codec="$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=nw=1:nk=1 "$OUTPUT_MP4")"
width="$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=nw=1:nk=1 "$OUTPUT_MP4")"
height="$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nw=1:nk=1 "$OUTPUT_MP4")"
rate="$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of default=nw=1:nk=1 "$OUTPUT_MP4")"
duration="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$OUTPUT_MP4")"

test "$codec" = h264
test "$width" = 3840
test "$height" = 2160
test "$rate" = 60/1
awk -v value="$duration" 'BEGIN { exit !(value >= 0.95 && value <= 1.10) }'

printf 'RENDER SMOKE: passed (%sx%s %s fps, %ss)\n' "$width" "$height" "$rate" "$duration"
