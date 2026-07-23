#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  printf 'usage: %s <video.mp4> <time-sec> <label-slug>\n' "$0" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_DIR/render_paths.sh"

for required_command in ffmpeg ffprobe realpath awk; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    printf 'extract-frame: missing command: %s\n' "$required_command" >&2
    exit 2
  fi
done

VIDEO_ABS="$(realpath "$1")"
TIME_SEC="$2"
LABEL="$3"
if [[ ! -f "$VIDEO_ABS" || "$VIDEO_ABS" != *.mp4 ]]; then
  printf 'extract-frame: video must be an existing MP4: %s\n' "$VIDEO_ABS" >&2
  exit 2
fi
if [[ ! "$LABEL" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
  printf 'extract-frame: label must be a lowercase kebab-case slug\n' >&2
  exit 2
fi

DURATION="$(
  ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 \
    "$VIDEO_ABS"
)"
if ! awk -v time="$TIME_SEC" -v duration="$DURATION" \
  'BEGIN { exit !(time ~ /^[0-9]+([.][0-9]+)?$/ && time >= 0 && time <= duration) }'; then
  printf 'extract-frame: time must be between 0 and %s seconds\n' "$DURATION" >&2
  exit 2
fi

STEM="$(basename "${VIDEO_ABS%.mp4}")"
TIME_MS="$(awk -v time="$TIME_SEC" 'BEGIN { printf "%09d", int(time * 1000 + 0.5) }')"
OUTPUT_DIR="$RENDER_FRAMES_DIR/$STEM"
OUTPUT_PNG="$OUTPUT_DIR/${STEM}--${TIME_MS}ms--${LABEL}.png"
mkdir -p "$OUTPUT_DIR"

ffmpeg -y -loglevel error -ss "$TIME_SEC" -i "$VIDEO_ABS" \
  -frames:v 1 "$OUTPUT_PNG"

printf 'extract-frame: completed %s\n' "$OUTPUT_PNG"
