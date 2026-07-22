#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REUSE=0
EPISODES=()

usage() {
  printf 'usage: %s [--reuse] [episode.json ...]\n' "$0" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --reuse)
      REUSE=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --*)
      printf 'narration: unknown option: %s\n' "$1" >&2
      usage
      exit 2
      ;;
    *)
      EPISODES+=("$1")
      shift
      ;;
  esac
done

for required_command in mmx jq ffprobe realpath sha256sum awk tr; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    printf 'narration: missing command: %s\n' "$required_command" >&2
    exit 2
  fi
done

if [[ "${#EPISODES[@]}" -eq 0 ]]; then
  while IFS= read -r -d '' path; do
    EPISODES+=("$path")
  done < <(
    find "$PROJECT_ROOT/content/episodes" -maxdepth 1 -type f \
      -name 's[0-9][0-9]e[0-9][0-9]-*.json' -print0 | sort -z
  )
fi

for episode_input in "${EPISODES[@]}"; do
  episode_abs="$(realpath "$episode_input")"
  stem="$(basename "${episode_abs%.json}")"
  script_value="$(jq -er '.narration.script' "$episode_abs")"
  if [[ "$script_value" != res://* ]]; then
    printf 'narration: script must use res:// path: %s\n' "$script_value" >&2
    exit 2
  fi
  narration_script="$PROJECT_ROOT/${script_value#res://}"
  if [[ ! -s "$narration_script" ]]; then
    printf 'narration: script not found or empty: %s\n' "$narration_script" >&2
    exit 2
  fi

  model="$(jq -r '.narration.model // "speech-2.8-hd"' "$episode_abs")"
  voice="$(jq -er '.narration.voice' "$episode_abs")"
  language="$(jq -r '.narration.language // "Chinese"' "$episode_abs")"
  speed="$(jq -r '.narration.speed // 1.0' "$episode_abs")"
  video_duration="$(jq -r '
    .story.question_sec
    + (.story.explain_sec // 0)
    + .story.setup_sec
    + .story.flight_sec
    + .story.compare_sec
  ' "$episode_abs")"

  output_dir="$PROJECT_ROOT/renders/narration/$stem"
  audio="$output_dir/narration.mp3"
  subtitles="$output_dir/narration.srt"
  manifest="$output_dir/narration.manifest.txt"
  mkdir -p "$output_dir"

  if [[ "$REUSE" -eq 0 ]]; then
    narration_tmp="$(mktemp -d /tmp/slingshot-narration.XXXXXX)"
    cleanup() {
      rm -rf "$narration_tmp"
    }
    trap cleanup EXIT
    mmx speech synthesize \
      --text-file "$narration_script" \
      --model "$model" \
      --voice "$voice" \
      --speed "$speed" \
      --language "$language" \
      --format mp3 \
      --sample-rate 32000 \
      --bitrate 128000 \
      --channels 1 \
      --subtitles \
      --out "$narration_tmp/narration.mp3" \
      --non-interactive \
      --quiet \
      --output json
    test -s "$narration_tmp/narration.mp3"
    test -s "$narration_tmp/narration.srt"
    mv "$narration_tmp/narration.mp3" "$audio"
    mv "$narration_tmp/narration.srt" "$subtitles"
    cleanup
    trap - EXIT
  elif [[ ! -s "$audio" || ! -s "$subtitles" ]]; then
    printf 'narration: --reuse requested but generated files are missing for %s\n' "$stem" >&2
    exit 2
  fi

  "$SCRIPT_DIR/verify_narration_sync.sh" "$episode_abs"
  "$SCRIPT_DIR/normalize_narration.sh" "$episode_abs"
  normalized_audio="$output_dir/narration-normalized.wav"
  loudness_report="$output_dir/narration-loudness.json"
  audio_duration="$(jq -r '.duration_sec' "$loudness_report")"
  if ! awk -v audio="$audio_duration" -v video="$video_duration" \
    'BEGIN { exit !(audio > 0 && audio <= video) }'; then
    printf 'narration: audio %.3fs exceeds video %.3fs for %s\n' \
      "$audio_duration" "$video_duration" "$stem" >&2
    exit 1
  fi

  {
    printf 'episode=%s\n' "$(basename "$episode_abs")"
    printf 'episode_sha256=%s\n' "$(sha256sum "$episode_abs" | awk '{print $1}')"
    printf 'script=%s\n' "$(basename "$narration_script")"
    printf 'script_sha256=%s\n' "$(sha256sum "$narration_script" | awk '{print $1}')"
    canonical_text="$(tr -d '[:space:]' <"$narration_script")"
    printf 'canonical_text_sha256=%s\n' \
      "$(printf '%s' "$canonical_text" | sha256sum | awk '{print $1}')"
    printf 'subtitle_text_exact=true\n'
    printf 'source_audio_sha256=%s\n' "$(sha256sum "$audio" | awk '{print $1}')"
    printf 'normalized_audio_sha256=%s\n' \
      "$(sha256sum "$normalized_audio" | awk '{print $1}')"
    printf 'subtitles_sha256=%s\n' "$(sha256sum "$subtitles" | awk '{print $1}')"
    printf 'audio_duration_sec=%s\n' "$audio_duration"
    printf 'video_duration_sec=%s\n' "$video_duration"
    printf 'model=%s\n' "$model"
    printf 'voice=%s\n' "$voice"
    printf 'speed=%s\n' "$speed"
		printf 'audio_standard=-16_LUFS_-1.5_dBTP_48kHz_mono_PCM24\n'
		printf 'audio_measured_i=%s\n' "$(jq -r '.measured_i' "$loudness_report")"
		printf 'audio_measured_tp=%s\n' "$(jq -r '.measured_tp' "$loudness_report")"
  } >"$manifest"

  printf 'narration: %s audio=%ss video=%ss\n' \
    "$stem" "$audio_duration" "$video_duration"
done
