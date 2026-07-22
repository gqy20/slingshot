#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  printf 'usage: %s <preset.json> [output.mp4]\n' "$0" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"

for required_command in "$GODOT_BIN" xvfb-run ffmpeg ffprobe realpath; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    printf 'render: missing command: %s\n' "$required_command" >&2
    exit 2
  fi
done

PRESET_ABS="$(realpath "$1")"
if [[ ! -f "$PRESET_ABS" ]]; then
  printf 'render: preset not found: %s\n' "$PRESET_ABS" >&2
  exit 2
fi

if [[ $# -eq 2 ]]; then
  OUTPUT_INPUT="$2"
else
  preset_name="$(basename "${PRESET_ABS%.json}")"
  OUTPUT_INPUT="$PROJECT_ROOT/renders/${preset_name}.mp4"
fi
if [[ "$OUTPUT_INPUT" != *.mp4 ]]; then
  printf 'render: output must end in .mp4: %s\n' "$OUTPUT_INPUT" >&2
  exit 2
fi

OUTPUT_DIR="$(dirname "$OUTPUT_INPUT")"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR_ABS="$(cd "$OUTPUT_DIR" && pwd)"
OUTPUT_MP4="$OUTPUT_DIR_ABS/$(basename "$OUTPUT_INPUT")"
OUTPUT_JSON="${OUTPUT_MP4%.mp4}.json"

RENDER_TMP="$(mktemp -d /tmp/slingshot-render.XXXXXX)"
FRAME_DIR="$RENDER_TMP/frames"
GODOT_LOG="$RENDER_TMP/godot.log"
MP4_TMP="$RENDER_TMP/output.mp4"
JSON_TMP="$RENDER_TMP/output.json"
mkdir -p "$FRAME_DIR"

render_succeeded=0
cleanup() {
  if [[ "$render_succeeded" -eq 1 ]]; then
    rm -rf "$RENDER_TMP"
  else
    printf 'render: failed; diagnostics preserved at %s\n' "$RENDER_TMP" >&2
  fi
}
trap cleanup EXIT

printf 'render: preset=%s\n' "$PRESET_ABS"
printf 'render: output=%s\n' "$OUTPUT_MP4"

if ! xvfb-run -a -s '-screen 0 3840x2160x24' \
  timeout "${RENDER_TIMEOUT_SEC:-900}" \
  "$GODOT_BIN" --path "$PROJECT_ROOT" \
  --rendering-method gl_compatibility \
  --resolution 3840x2160 \
  --write-movie "$FRAME_DIR/frame.png" \
  --fixed-fps 60 --disable-vsync \
  -- --preset "$PRESET_ABS" --sidecar "$JSON_TMP" \
  >"$GODOT_LOG" 2>&1; then
  sed -n '1,240p' "$GODOT_LOG" >&2
  exit 1
fi

if grep -Eq 'SCRIPT ERROR|^ERROR:' "$GODOT_LOG"; then
  sed -n '1,240p' "$GODOT_LOG" >&2
  exit 1
fi
if ! compgen -G "$FRAME_DIR/frame*.png" >/dev/null; then
  printf 'render: Godot produced no PNG frames\n' >&2
  exit 1
fi
if [[ ! -s "$JSON_TMP" ]]; then
  printf 'render: Godot produced no telemetry sidecar\n' >&2
  exit 1
fi

ffmpeg -y -loglevel error \
  -framerate 60 -i "$FRAME_DIR/frame%08d.png" \
  -c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p \
  -movflags +faststart -an "$MP4_TMP"

probe="$(ffprobe -v error -select_streams v:0 \
  -show_entries stream=codec_name,width,height,avg_frame_rate \
  -of csv=p=0 "$MP4_TMP")"
if [[ "$probe" != 'h264,3840,2160,60/1' ]]; then
  printf 'render: unexpected stream metadata: %s\n' "$probe" >&2
  exit 1
fi

mv "$MP4_TMP" "$OUTPUT_MP4"
mv "$JSON_TMP" "$OUTPUT_JSON"
render_succeeded=1

printf 'render: completed %s\n' "$OUTPUT_MP4"
printf 'render: telemetry %s\n' "$OUTPUT_JSON"
