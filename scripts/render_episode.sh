#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  printf 'usage: %s <episode.json> [output.mp4]\n' "$0" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"

for required_command in "$GODOT_BIN" xvfb-run ffmpeg ffprobe realpath sha256sum timeout jq awk; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    printf 'episode-render: missing command: %s\n' "$required_command" >&2
    exit 2
  fi
done

EPISODE_ABS="$(realpath "$1")"
if [[ ! -f "$EPISODE_ABS" ]]; then
  printf 'episode-render: episode not found: %s\n' "$EPISODE_ABS" >&2
  exit 2
fi
episode_name="$(basename "${EPISODE_ABS%.json}")"
FPS="$(jq -er '.video.fps' "$EPISODE_ABS")"
VIDEO_DURATION="$(jq -r '
  .story.question_sec
  + (.story.explain_sec // 0)
  + .story.setup_sec
  + .story.flight_sec
  + .story.compare_sec
' "$EPISODE_ABS")"
if [[ "$FPS" != 30 && "$FPS" != 60 ]]; then
  printf 'episode-render: video fps must be 30 or 60, got %s\n' "$FPS" >&2
  exit 2
fi

if [[ $# -eq 2 ]]; then
  OUTPUT_INPUT="$2"
else
  OUTPUT_INPUT="$PROJECT_ROOT/renders/episodes/${episode_name}.mp4"
fi
if [[ "$OUTPUT_INPUT" != *.mp4 ]]; then
  printf 'episode-render: output must end in .mp4: %s\n' "$OUTPUT_INPUT" >&2
  exit 2
fi

OUTPUT_DIR="$(dirname "$OUTPUT_INPUT")"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR_ABS="$(cd "$OUTPUT_DIR" && pwd)"
OUTPUT_MP4="$OUTPUT_DIR_ABS/$(basename "$OUTPUT_INPUT")"
OUTPUT_JSON="${OUTPUT_MP4%.mp4}.json"
OUTPUT_MANIFEST="${OUTPUT_MP4%.mp4}.manifest.txt"
NARRATION_DIR="$PROJECT_ROOT/renders/narration/$episode_name"
NARRATION_AUDIO="${NARRATION_AUDIO:-$NARRATION_DIR/narration.mp3}"
SUBTITLE_SRT="${SUBTITLE_SRT:-$NARRATION_DIR/narration.srt}"
HAS_NARRATION="$(jq -r '(.narration // {}) | length > 0' "$EPISODE_ABS")"
if [[ "$HAS_NARRATION" == true ]]; then
  if [[ ! -s "$NARRATION_AUDIO" || ! -s "$SUBTITLE_SRT" ]]; then
    printf 'episode-render: narration missing; run scripts/generate_narration.sh %s\n' \
      "$EPISODE_ABS" >&2
    exit 2
  fi
  audio_duration="$(
    ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 \
      "$NARRATION_AUDIO"
  )"
  if ! awk -v audio="$audio_duration" -v video="$VIDEO_DURATION" \
    'BEGIN { exit !(audio > 0 && audio <= video) }'; then
    printf 'episode-render: narration %.3fs exceeds video %.3fs\n' \
      "$audio_duration" "$VIDEO_DURATION" >&2
    exit 2
  fi
fi

RENDER_TMP="$(mktemp -d /tmp/slingshot-episode.XXXXXX)"
FRAME_DIR="$RENDER_TMP/frames"
SIMULATION_LOG="$RENDER_TMP/simulation.log"
RENDER_LOG="$RENDER_TMP/render.log"
RECORD_TMP="$RENDER_TMP/run-record.json"
MP4_TMP="$RENDER_TMP/output.mp4"
JSON_TMP="$RENDER_TMP/output.json"
MANIFEST_TMP="$RENDER_TMP/manifest.txt"
mkdir -p "$FRAME_DIR"

render_succeeded=0
cleanup() {
  if [[ "$render_succeeded" -eq 1 ]]; then
    rm -rf "$RENDER_TMP"
  else
    printf 'episode-render: failed; diagnostics preserved at %s\n' "$RENDER_TMP" >&2
  fi
}
trap cleanup EXIT

printf 'episode-render: simulate=%s\n' "$EPISODE_ABS"
if ! timeout "${SIMULATION_TIMEOUT_SEC:-300}"   "$GODOT_BIN" --headless --path "$PROJECT_ROOT"   --fixed-fps 120 --disable-vsync   res://episode.tscn   -- --episode "$EPISODE_ABS" --simulate-record "$RECORD_TMP"   >"$SIMULATION_LOG" 2>&1; then
  sed -n '1,260p' "$SIMULATION_LOG" >&2
  exit 1
fi
if grep -Eq 'SCRIPT ERROR|^ERROR:' "$SIMULATION_LOG" || [[ ! -s "$RECORD_TMP" ]]; then
  sed -n '1,260p' "$SIMULATION_LOG" >&2
  exit 1
fi

printf 'episode-render: render=%s\n' "$OUTPUT_MP4"
PLAYBACK_ARGS=(
  --episode "$EPISODE_ABS"
  --play-record "$RECORD_TMP"
  --sidecar "$JSON_TMP"
)
if [[ "$HAS_NARRATION" == true ]]; then
  PLAYBACK_ARGS+=(--subtitles "$SUBTITLE_SRT")
fi
if ! xvfb-run -a -s '-screen 0 1920x1080x24' \
  timeout "${RENDER_TIMEOUT_SEC:-1200}" \
  "$GODOT_BIN" --path "$PROJECT_ROOT" \
  --rendering-method gl_compatibility \
  --resolution 1920x1080 \
  --write-movie "$FRAME_DIR/frame.png" \
  --fixed-fps "$FPS" --disable-vsync \
  res://episode.tscn -- "${PLAYBACK_ARGS[@]}" \
  >"$RENDER_LOG" 2>&1; then
  sed -n '1,260p' "$RENDER_LOG" >&2
  exit 1
fi
if grep -Eq 'SCRIPT ERROR|^ERROR:' "$RENDER_LOG"; then
  sed -n '1,260p' "$RENDER_LOG" >&2
  exit 1
fi
if ! compgen -G "$FRAME_DIR/frame*.png" >/dev/null; then
  printf 'episode-render: Godot produced no PNG frames\n' >&2
  exit 1
fi
if [[ ! -s "$JSON_TMP" ]]; then
  printf 'episode-render: Godot produced no episode sidecar\n' >&2
  exit 1
fi

if [[ "$HAS_NARRATION" == true ]]; then
  ffmpeg -y -loglevel error \
    -framerate "$FPS" -i "$FRAME_DIR/frame%08d.png" \
    -i "$NARRATION_AUDIO" \
    -t "$VIDEO_DURATION" \
    -c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p \
    -c:a aac -b:a 160k \
    -af 'loudnorm=I=-16:TP=-1.5:LRA=7,aresample=48000' \
    -movflags +faststart "$MP4_TMP"
else
  ffmpeg -y -loglevel error \
    -framerate "$FPS" -i "$FRAME_DIR/frame%08d.png" \
    -t "$VIDEO_DURATION" \
    -c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p \
    -movflags +faststart -an "$MP4_TMP"
fi

probe="$(ffprobe -v error -select_streams v:0   -show_entries stream=codec_name,width,height,avg_frame_rate   -of csv=p=0 "$MP4_TMP")"
if [[ "$probe" != "h264,1920,1080,$FPS/1" ]]; then
  printf 'episode-render: unexpected stream metadata: %s\n' "$probe" >&2
  exit 1
fi
output_duration="$(
  ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$MP4_TMP"
)"
if ! awk -v actual="$output_duration" -v expected="$VIDEO_DURATION" \
  'BEGIN { delta = actual - expected; if (delta < 0) delta = -delta; exit !(delta <= 0.05) }'; then
  printf 'episode-render: unexpected duration: %s (expected %s)\n' \
    "$output_duration" "$VIDEO_DURATION" >&2
  exit 1
fi
if [[ "$HAS_NARRATION" == true ]]; then
  audio_codec="$(
    ffprobe -v error -select_streams a:0 -show_entries stream=codec_name \
      -of default=nw=1:nk=1 "$MP4_TMP"
  )"
  if [[ "$audio_codec" != aac ]]; then
    printf 'episode-render: expected AAC narration, got %s\n' "$audio_codec" >&2
    exit 1
  fi
fi

mp4_sha="$(sha256sum "$MP4_TMP" | awk '{print $1}')"
episode_sha="$(sha256sum "$EPISODE_ABS" | awk '{print $1}')"
record_sha="$(sha256sum "$RECORD_TMP" | awk '{print $1}')"
godot_version="$("$GODOT_BIN" --version | head -1)"
{
  printf 'episode=%s\n' "$(basename "$EPISODE_ABS")"
  printf 'episode_sha256=%s\n' "$episode_sha"
  printf 'record_sha256=%s\n' "$record_sha"
  printf 'video_sha256=%s\n' "$mp4_sha"
  printf 'video_stream=%s\n' "$probe"
  printf 'video_duration_sec=%s\n' "$output_duration"
	if [[ "$HAS_NARRATION" == true ]]; then
		printf 'audio_sha256=%s\n' "$(sha256sum "$NARRATION_AUDIO" | awk '{print $1}')"
		printf 'subtitles_sha256=%s\n' "$(sha256sum "$SUBTITLE_SRT" | awk '{print $1}')"
		printf 'audio_codec=aac\n'
		printf 'audio_loudness_target=-16_LUFS\n'
	fi
  printf 'engine=%s\n' "$godot_version"
  printf 'renderer=gl_compatibility\n'
  printf 'deterministic_seeded=true\n'
} >"$MANIFEST_TMP"

mv "$MP4_TMP" "$OUTPUT_MP4"
mv "$JSON_TMP" "$OUTPUT_JSON"
mv "$MANIFEST_TMP" "$OUTPUT_MANIFEST"
render_succeeded=1

printf 'episode-render: completed %s\n' "$OUTPUT_MP4"
printf 'episode-render: analysis %s\n' "$OUTPUT_JSON"
printf 'episode-render: manifest %s\n' "$OUTPUT_MANIFEST"
