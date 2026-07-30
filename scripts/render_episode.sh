#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  printf 'usage: %s <episode.json> [output.mp4]\n' "$0" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_DIR/render_paths.sh"
GODOT_BIN="${GODOT_BIN:-godot}"
FFMPEG_BIN="${FFMPEG_BIN:-}"

if [[ -z "$FFMPEG_BIN" ]]; then
	for ffmpeg_candidate in /usr/bin/ffmpeg "$(command -v ffmpeg 2>/dev/null || true)"; do
		if [[ -x "$ffmpeg_candidate" ]] \
			&& "$ffmpeg_candidate" -hide_banner -filters 2>/dev/null \
				| awk '$2 == "subtitles" { found = 1 } END { exit !found }'; then
			FFMPEG_BIN="$ffmpeg_candidate"
			break
		fi
	done
fi
if [[ -z "$FFMPEG_BIN" ]]; then
	printf 'episode-render: ffmpeg with libass subtitles support is required\n' >&2
	exit 2
fi

for required_command in "$GODOT_BIN" "$FFMPEG_BIN" xvfb-run ffprobe realpath sha256sum timeout jq awk; do
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
"$SCRIPT_DIR/build_formula_assets.sh" "$EPISODE_ABS"
episode_name="$(basename "${EPISODE_ABS%.json}")"
FORMULA_ASSET_DIR="$(jq -r '.story.explanation.asset_dir // ""' "$EPISODE_ABS")"
FORMULA_ASSET_MANIFEST=""
if [[ -n "$FORMULA_ASSET_DIR" ]]; then
  FORMULA_ASSET_MANIFEST="$PROJECT_ROOT/${FORMULA_ASSET_DIR#res://}/formulas.manifest.txt"
fi
FPS="$(jq -er '.video.fps' "$EPISODE_ABS")"
SOURCE_WIDTH="$(jq -er '.video.width' "$EPISODE_ABS")"
SOURCE_HEIGHT="$(jq -er '.video.height' "$EPISODE_ABS")"
WIDTH="${EPISODE_RENDER_WIDTH:-$SOURCE_WIDTH}"
HEIGHT="${EPISODE_RENDER_HEIGHT:-$SOURCE_HEIGHT}"
VIDEO_DURATION="$(jq -r '
  .story.question_sec
  + (.story.explain_sec // 0)
  + .story.setup_sec
  + .story.flight_sec
  + .story.compare_sec
' "$EPISODE_ABS")"
TOTAL_FRAMES="$(awk -v duration="$VIDEO_DURATION" -v fps="$FPS" \
  'BEGIN { printf "%d", duration * fps + 0.5 }')"
RENDER_WORKERS="${EPISODE_RENDER_WORKERS:-1}"
MIN_FRAMES_PER_SHARD="${EPISODE_SHARD_MIN_FRAMES:-300}"
CAPTURE_REPEAT="${EPISODE_CAPTURE_REPEAT:-2}"
SUBTITLE_FONT_SIZE="${EPISODE_SUBTITLE_FONT_SIZE:-42}"
SUBTITLE_BOTTOM_MARGIN="${EPISODE_SUBTITLE_BOTTOM_MARGIN:-100}"
if [[ ! "$RENDER_WORKERS" =~ ^[1-9][0-9]*$ ]]; then
  printf 'episode-render: EPISODE_RENDER_WORKERS must be a positive integer\n' >&2
  exit 2
fi
if [[ ! "$MIN_FRAMES_PER_SHARD" =~ ^[1-9][0-9]*$ ]]; then
  printf 'episode-render: EPISODE_SHARD_MIN_FRAMES must be a positive integer\n' >&2
  exit 2
fi
if [[ ! "$CAPTURE_REPEAT" =~ ^[1-9][0-9]*$ ]]; then
	printf 'episode-render: EPISODE_CAPTURE_REPEAT must be a positive integer\n' >&2
	exit 2
fi
# Multiple Vulkan movie-writer processes backed by llvmpipe can corrupt each
# other's CanvasItem passes even when every process owns a separate X server.
# Keep a single episode serial: batch-level concurrency remains available for
# machines with several independent render jobs, but one movie never shards.
if [[ "$RENDER_WORKERS" -gt 1 ]]; then
	printf 'episode-render: capping workers %s -> 1 for coherent movie capture\n' \
		"$RENDER_WORKERS"
	RENDER_WORKERS=1
fi
max_workers_by_length=$((TOTAL_FRAMES / MIN_FRAMES_PER_SHARD))
if [[ "$max_workers_by_length" -lt 1 ]]; then
  max_workers_by_length=1
fi
if [[ "$RENDER_WORKERS" -gt "$max_workers_by_length" ]]; then
  RENDER_WORKERS="$max_workers_by_length"
fi
if [[ "$RENDER_WORKERS" -gt "$TOTAL_FRAMES" ]]; then
  RENDER_WORKERS="$TOTAL_FRAMES"
fi
if [[ "$FPS" != 30 && "$FPS" != 60 ]]; then
  printf 'episode-render: video fps must be 30 or 60, got %s\n' "$FPS" >&2
  exit 2
fi
if [[ "$SOURCE_WIDTH,$SOURCE_HEIGHT" != '3840,2160' ]]; then
	printf 'episode-render: episode master resolution must be 3840x2160\n' >&2
	exit 2
fi
if [[ "$WIDTH,$HEIGHT" != '3840,2160' && "$WIDTH,$HEIGHT" != '1920,1080' ]]; then
	printf 'episode-render: render resolution must be 3840x2160 or 1920x1080\n' >&2
	exit 2
fi

if [[ $# -eq 2 ]]; then
  OUTPUT_INPUT="$2"
else
	if [[ "$WIDTH,$HEIGHT" == '1920,1080' ]]; then
		OUTPUT_INPUT="$(episode_preview_dir "$episode_name")/episode-preview.mp4"
	else
		OUTPUT_INPUT="$(episode_master_dir "$episode_name")/program-master-4k.mp4"
	fi
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
OUTPUT_CLEAN_MASTER="$(episode_master_dir "$episode_name")/picture-clean-4k.mp4"
NARRATION_DIR="$(episode_audio_dir "$episode_name")"
NARRATION_SOURCE="$NARRATION_DIR/narration.mp3"
NARRATION_AUDIO="${NARRATION_AUDIO:-$NARRATION_DIR/narration-normalized.wav}"
LOUDNESS_REPORT="$NARRATION_DIR/narration-loudness.json"
SUBTITLE_SRT="${SUBTITLE_SRT:-$NARRATION_DIR/narration.srt}"
EDITORIAL_SUBTITLE="$(jq -r '.narration.subtitle_script // empty' "$EPISODE_ABS")"
if [[ -n "$EDITORIAL_SUBTITLE" ]]; then
	if [[ "$EDITORIAL_SUBTITLE" != res://* || "$EDITORIAL_SUBTITLE" == *..* ]]; then
		printf 'episode-render: unsafe narration.subtitle_script: %s\n' "$EDITORIAL_SUBTITLE" >&2
		exit 2
	fi
	SUBTITLE_SRT="$PROJECT_ROOT/${EDITORIAL_SUBTITLE#res://}"
fi
if [[ ! "$SUBTITLE_FONT_SIZE" =~ ^[1-9][0-9]*$ || ! "$SUBTITLE_BOTTOM_MARGIN" =~ ^[1-9][0-9]*$ ]]; then
	printf 'episode-render: subtitle font size and bottom margin must be positive integers\n' >&2
	exit 2
fi
SOUND_DESIGN_AUDIO="$(episode_audio_dir "$episode_name")/sound-design.wav"
HAS_NARRATION="$(jq -r '(.narration // {}) | length > 0' "$EPISODE_ABS")"
if [[ "${EPISODE_SKIP_NARRATION:-0}" == 1 ]]; then
	HAS_NARRATION=false
fi
if [[ "$HAS_NARRATION" == true ]]; then
  "$SCRIPT_DIR/verify_narration_sync.sh" "$EPISODE_ABS"
  "$SCRIPT_DIR/normalize_narration.sh" "$EPISODE_ABS"
  "$SCRIPT_DIR/build_sound_design.sh" "$EPISODE_ABS"
  if [[ ! -s "$NARRATION_AUDIO" || ! -s "$SUBTITLE_SRT" || ! -s "$LOUDNESS_REPORT" ]]; then
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
SHARD_DIR="$RENDER_TMP/shards"
PROJECT_VIEW="$RENDER_TMP/project"
SIMULATION_LOG="$RENDER_TMP/simulation.log"
RECORD_TMP="$RENDER_TMP/run-record.json"
MP4_TMP="$RENDER_TMP/output.mp4"
CLEAN_MASTER_TMP="$RENDER_TMP/clean-master.mp4"
JSON_TMP="$RENDER_TMP/output.json"
MANIFEST_TMP="$RENDER_TMP/manifest.txt"
SUBTITLE_RENDER_SRT="$RENDER_TMP/subtitles-render.srt"
SUBTITLE_ASS="$RENDER_TMP/subtitles.ass"
mkdir -p "$FRAME_DIR" "$SHARD_DIR" "$PROJECT_VIEW"

# Movie Maker allocates its recording viewport before EpisodeApp can resize the
# root window. A per-render project view lets override.cfg select the real frame
# buffer size without mutating project.godot or racing parallel renders.
for project_entry in project.godot episode.tscn assets content presets src; do
  ln -s "$PROJECT_ROOT/$project_entry" "$PROJECT_VIEW/$project_entry"
done
if [[ -d "$PROJECT_ROOT/.godot" ]]; then
  ln -s "$PROJECT_ROOT/.godot" "$PROJECT_VIEW/.godot"
fi
{
  printf '[display]\n'
  printf 'window/size/viewport_width=%s\n' "$WIDTH"
  printf 'window/size/viewport_height=%s\n' "$HEIGHT"
  printf 'window/stretch/mode="disabled"\n'
} >"$PROJECT_VIEW/override.cfg"

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

printf 'episode-render: render=%s workers=%s frames=%s\n' \
  "$OUTPUT_MP4" "$RENDER_WORKERS" "$TOTAL_FRAMES"
PLAYBACK_ARGS=(
	--episode "$EPISODE_ABS"
	--play-record "$RECORD_TMP"
	--render-width "$WIDTH"
	--render-height "$HEIGHT"
	--capture-repeat "$CAPTURE_REPEAT"
)
if [[ "$HAS_NARRATION" == true ]]; then
	# Keep subtitle cues in the sidecar, but composite their visible text after
	# Godot renders the picture. Visible subtitle Controls make software Movie
	# Writer alternate between incomplete Canvas passes.
	PLAYBACK_ARGS+=(--subtitles "$SUBTITLE_SRT" --external-subtitles)
fi
XVFB_SCREEN="-screen 0 ${WIDTH}x${HEIGHT}x24"
render_pids=()
for ((shard_index = 0; shard_index < RENDER_WORKERS; shard_index += 1)); do
  frame_start=$((TOTAL_FRAMES * shard_index / RENDER_WORKERS))
  frame_end=$((TOTAL_FRAMES * (shard_index + 1) / RENDER_WORKERS))
  shard_frames="$SHARD_DIR/shard-$(printf '%02d' "$shard_index")"
  shard_log="$SHARD_DIR/shard-$(printf '%02d' "$shard_index").log"
  mkdir -p "$shard_frames"
  shard_args=(
    "${PLAYBACK_ARGS[@]}"
    --frame-start "$frame_start"
    --frame-end "$frame_end"
  )
  if [[ "$shard_index" -eq 0 ]]; then
    shard_args+=(--sidecar "$JSON_TMP")
  fi
  printf 'episode-render: shard=%s frames=[%s,%s)\n' \
    "$shard_index" "$frame_start" "$frame_end"
  (
    # The OpenGL compatibility renderer intermittently captures the stale X11
    # back buffer under Xvfb/llvmpipe, producing alternating incomplete frames.
    # Selecting the Mobile method alone can still fall back to OpenGL, so pin
    # the Vulkan driver explicitly to keep movie-writer frames coherent.
    if ! xvfb-run -a -s "$XVFB_SCREEN" \
      timeout "${RENDER_TIMEOUT_SEC:-3600}" \
      "$GODOT_BIN" --path "$PROJECT_VIEW" \
      --rendering-method mobile \
      --rendering-driver vulkan \
      --resolution "${WIDTH}x${HEIGHT}" \
      --write-movie "$shard_frames/frame.png" \
      --fixed-fps "$((FPS * CAPTURE_REPEAT))" --disable-vsync \
      res://episode.tscn -- "${shard_args[@]}" \
      >"$shard_log" 2>&1; then
      sed -n '1,260p' "$shard_log" >&2
      exit 1
    fi
    if grep -Eq 'SCRIPT ERROR|^ERROR:' "$shard_log"; then
      sed -n '1,260p' "$shard_log" >&2
      exit 1
    fi
  ) &
  render_pids+=("$!")
done

render_failed=0
for render_pid in "${render_pids[@]}"; do
  if ! wait "$render_pid"; then
    render_failed=1
  fi
done
if [[ "$render_failed" -ne 0 ]]; then
  printf 'episode-render: one or more render shards failed\n' >&2
  exit 1
fi

merged_frames=0
for ((shard_index = 0; shard_index < RENDER_WORKERS; shard_index += 1)); do
  frame_start=$((TOTAL_FRAMES * shard_index / RENDER_WORKERS))
  frame_end=$((TOTAL_FRAMES * (shard_index + 1) / RENDER_WORKERS))
  expected_frames=$(((frame_end - frame_start) * CAPTURE_REPEAT))
  shard_frames="$SHARD_DIR/shard-$(printf '%02d' "$shard_index")"
  actual_frames="$(find "$shard_frames" -maxdepth 1 -name 'frame*.png' -printf '.' | wc -c)"
  if [[ "$actual_frames" -ne "$expected_frames" ]]; then
    printf 'episode-render: shard %s produced %s frames, expected %s\n' \
      "$shard_index" "$actual_frames" "$expected_frames" >&2
    exit 1
  fi
  raw_frame_index=0
  while IFS= read -r local_frame; do
    if ((raw_frame_index % CAPTURE_REPEAT == CAPTURE_REPEAT - 1)); then
      printf -v merged_name 'frame%08d.png' "$merged_frames"
      mv "$local_frame" "$FRAME_DIR/$merged_name"
      merged_frames=$((merged_frames + 1))
    fi
    raw_frame_index=$((raw_frame_index + 1))
  done < <(find "$shard_frames" -maxdepth 1 -name 'frame*.png' -print | sort)
done
if [[ "$merged_frames" -ne "$TOTAL_FRAMES" ]]; then
  printf 'episode-render: merged %s frames, expected %s\n' \
    "$merged_frames" "$TOTAL_FRAMES" >&2
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
	"$GODOT_BIN" --headless --path "$PROJECT_ROOT" \
		--script res://scripts/export_subtitles.gd -- \
		"$SUBTITLE_SRT" "$SUBTITLE_RENDER_SRT"
	"$FFMPEG_BIN" -y -loglevel error -i "$SUBTITLE_RENDER_SRT" "$SUBTITLE_ASS"
	sed -i \
		-e 's/^PlayResX:.*/PlayResX: 1920/' \
		-e 's/^PlayResY:.*/PlayResY: 1080/' \
		-e "s|^Style: Default,.*|Style: Default,Sarasa Gothic SC,$SUBTITLE_FONT_SIZE,\&H00E9F0F2,\&H00E9F0F2,\&H60050608,\&H00050608,-1,0,0,0,100,100,0,0,1,2,0,2,190,190,$SUBTITLE_BOTTOM_MARGIN,1|" \
		"$SUBTITLE_ASS"
	SUBTITLE_FILTER="subtitles=filename='$SUBTITLE_ASS':fontsdir='$PROJECT_ROOT/assets/fonts'"
	"$FFMPEG_BIN" -y -loglevel error \
		-framerate "$FPS" -i "$FRAME_DIR/frame%08d.png" \
		-i "$NARRATION_AUDIO" -i "$SOUND_DESIGN_AUDIO" \
		-t "$VIDEO_DURATION" \
		-filter_complex "[0:v]$SUBTITLE_FILTER[vout];[2:a]volume=0.40[sfx];[sfx][1:a]sidechaincompress=threshold=0.015:ratio=8:attack=15:release=300[sfxduck];[1:a][sfxduck]amix=inputs=2:duration=longest:normalize=0,alimiter=limit=0.78:level=false[aout]" \
		-map '[vout]' -map '[aout]' \
    -c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p \
    -c:a aac -b:a 192k \
    -movflags +faststart "$MP4_TMP"
else
  "$FFMPEG_BIN" -y -loglevel error \
    -framerate "$FPS" -i "$FRAME_DIR/frame%08d.png" \
    -t "$VIDEO_DURATION" \
    -c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p \
    -movflags +faststart -an "$MP4_TMP"
fi

probe="$(ffprobe -v error -select_streams v:0   -show_entries stream=codec_name,width,height,avg_frame_rate   -of csv=p=0 "$MP4_TMP")"
if [[ "$probe" != "h264,$WIDTH,$HEIGHT,$FPS/1" ]]; then
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

# A full 4K release render also keeps a high-quality, subtitle-free picture
# master. Subtitle styling, copy, narration, SFX, and BGM can then be revised
# without running Godot frame capture again.
preserve_clean_master=false
clean_master_sha=none
clean_master_probe=none
if [[ "$HAS_NARRATION" == true && "$WIDTH,$HEIGHT" == '3840,2160' ]]; then
  preserve_clean_master=true
  "$FFMPEG_BIN" -y -loglevel error \
    -framerate "$FPS" -i "$FRAME_DIR/frame%08d.png" \
    -t "$VIDEO_DURATION" \
    -c:v libx264 -preset medium -crf 14 -pix_fmt yuv420p \
    -movflags +faststart -an "$CLEAN_MASTER_TMP"
  clean_master_probe="$(ffprobe -v error -select_streams v:0 \
    -show_entries stream=codec_name,width,height,avg_frame_rate \
    -of csv=p=0 "$CLEAN_MASTER_TMP")"
  if [[ "$clean_master_probe" != "h264,$WIDTH,$HEIGHT,$FPS/1" ]]; then
    printf 'episode-render: unexpected clean master metadata: %s\n' \
      "$clean_master_probe" >&2
    exit 1
  fi
  clean_master_duration="$(ffprobe -v error -show_entries format=duration \
    -of default=nw=1:nk=1 "$CLEAN_MASTER_TMP")"
  if ! awk -v actual="$clean_master_duration" -v expected="$VIDEO_DURATION" \
    'BEGIN { delta = actual - expected; if (delta < 0) delta = -delta; exit !(delta <= 0.05) }'; then
    printf 'episode-render: unexpected clean master duration: %s (expected %s)\n' \
      "$clean_master_duration" "$VIDEO_DURATION" >&2
    exit 1
  fi
  clean_master_sha="$(sha256sum "$CLEAN_MASTER_TMP" | awk '{print $1}')"
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
  delivery_audio_json="$("$SCRIPT_DIR/verify_delivery_audio.sh" "$MP4_TMP")"
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
	if [[ -n "$FORMULA_ASSET_MANIFEST" ]]; then
		printf 'formula_renderer=typst_svg\n'
		printf 'formula_assets_sha256=%s\n' "$(sha256sum "$FORMULA_ASSET_MANIFEST" | awk '{print $1}')"
	fi
	if [[ "$HAS_NARRATION" == true ]]; then
		printf 'audio_source_sha256=%s\n' "$(sha256sum "$NARRATION_SOURCE" | awk '{print $1}')"
		printf 'audio_normalized_sha256=%s\n' "$(sha256sum "$NARRATION_AUDIO" | awk '{print $1}')"
		printf 'subtitles_sha256=%s\n' "$(sha256sum "$SUBTITLE_SRT" | awk '{print $1}')"
		printf 'sound_design_sha256=%s\n' "$(sha256sum "$SOUND_DESIGN_AUDIO" | awk '{print $1}')"
		printf 'audio_mix=voice_plus_ducked_beat_sfx\n'
		printf 'audio_codec=aac\n'
		printf 'audio_standard=-16_LUFS_-1.5_dBTP_48kHz_mono_PCM24_source\n'
		printf 'audio_measured_i=%s\n' "$(jq -r '.measured_i' "$LOUDNESS_REPORT")"
		printf 'audio_measured_tp=%s\n' "$(jq -r '.measured_tp' "$LOUDNESS_REPORT")"
		printf 'audio_delivery_standard=-16_LUFS_plus_minus_1_-1.0_dBTP_max_48kHz_mono\n'
		printf 'audio_delivery_measured_i=%s\n' "$(jq -r '.measured_i' <<<"$delivery_audio_json")"
		printf 'audio_delivery_measured_tp=%s\n' "$(jq -r '.measured_tp' <<<"$delivery_audio_json")"
		printf 'subtitle_text_exact=true\n'
		printf 'subtitle_renderer=ffmpeg_libass\n'
		printf 'subtitle_font_size=%s\n' "$SUBTITLE_FONT_SIZE"
		printf 'subtitle_bottom_margin=%s\n' "$SUBTITLE_BOTTOM_MARGIN"
	fi
	printf 'clean_master=%s\n' "$(if [[ "$preserve_clean_master" == true ]]; then basename "$OUTPUT_CLEAN_MASTER"; else printf 'not_created'; fi)"
	printf 'clean_master_sha256=%s\n' "$clean_master_sha"
	printf 'clean_master_stream=%s\n' "$clean_master_probe"
	printf 'clean_master_subtitles=none\n'
	printf 'clean_master_audio=none\n'
	printf 'clean_master_purpose=subtitle_audio_bgm_reburn_without_godot\n'
  printf 'engine=%s\n' "$godot_version"
	printf 'renderer=mobile_vulkan\n'
	printf 'render_resolution=%sx%s\n' "$WIDTH" "$HEIGHT"
	printf 'render_workers=%s\n' "$RENDER_WORKERS"
	printf 'capture_repeat=%s\n' "$CAPTURE_REPEAT"
	if [[ "$CAPTURE_REPEAT" -eq 1 ]]; then
		printf 'capture_buffer_parity=direct\n'
	else
		printf 'capture_buffer_parity=last_of_repeat\n'
	fi
	printf 'render_sharding=absolute_frame_ranges\n'
  printf 'deterministic_seeded=true\n'
} >"$MANIFEST_TMP"

mv "$MP4_TMP" "$OUTPUT_MP4"
if [[ "$preserve_clean_master" == true ]]; then
  mv "$CLEAN_MASTER_TMP" "$OUTPUT_CLEAN_MASTER"
fi
mv "$JSON_TMP" "$OUTPUT_JSON"
mv "$MANIFEST_TMP" "$OUTPUT_MANIFEST"
render_succeeded=1

printf 'episode-render: completed %s\n' "$OUTPUT_MP4"
printf 'episode-render: analysis %s\n' "$OUTPUT_JSON"
printf 'episode-render: manifest %s\n' "$OUTPUT_MANIFEST"
if [[ "$preserve_clean_master" == true ]]; then
  printf 'episode-render: clean master %s\n' "$OUTPUT_CLEAN_MASTER"
fi
