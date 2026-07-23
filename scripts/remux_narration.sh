#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  printf 'usage: %s <episode.json> [episode.mp4]\n' "$0" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_DIR/render_paths.sh"
for required_command in ffmpeg ffprobe jq realpath sha256sum awk; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    printf 'narration-remux: missing command: %s\n' "$required_command" >&2
    exit 2
  fi
done

episode_abs="$(realpath "$1")"
stem="$(basename "${episode_abs%.json}")"
if [[ $# -eq 2 ]]; then
  video_abs="$(realpath "$2")"
else
  video_abs="$RENDER_FINAL_DIR/$stem.mp4"
fi
source_audio="$RENDER_NARRATION_DIR/$stem/narration.mp3"
"$SCRIPT_DIR/verify_narration_sync.sh" "$episode_abs"
"$SCRIPT_DIR/normalize_narration.sh" "$episode_abs"
"$SCRIPT_DIR/build_sound_design.sh" "$episode_abs"
audio="$RENDER_NARRATION_DIR/$stem/narration-normalized.wav"
sound_design="$RENDER_AUDIO_DIR/$stem/sound-design.wav"
loudness_report="$RENDER_NARRATION_DIR/$stem/narration-loudness.json"
subtitles="$RENDER_NARRATION_DIR/$stem/narration.srt"
manifest="${video_abs%.mp4}.manifest.txt"
for required_file in "$episode_abs" "$video_abs" "$source_audio" "$audio" \
  "$sound_design" "$loudness_report" "$subtitles" "$manifest"; do
  if [[ ! -s "$required_file" ]]; then
    printf 'narration-remux: required file missing: %s\n' "$required_file" >&2
    exit 2
  fi
done

video_duration="$(jq -r '
  .story.question_sec
  + (.story.explain_sec // 0)
  + .story.setup_sec
  + .story.flight_sec
  + .story.compare_sec
' "$episode_abs")"
remux_tmp="$(mktemp -d /tmp/slingshot-remux.XXXXXX)"
cleanup() {
  rm -rf "$remux_tmp"
}
trap cleanup EXIT

ffmpeg -y -loglevel error \
  -i "$video_abs" -i "$audio" -i "$sound_design" \
  -filter_complex '[2:a]volume=0.70[sfx];[sfx][1:a]sidechaincompress=threshold=0.02:ratio=6:attack=20:release=250[sfxduck];[1:a][sfxduck]amix=inputs=2:duration=longest:normalize=0,alimiter=limit=0.89[aout]' \
  -map 0:v:0 -map '[aout]' \
  -t "$video_duration" \
  -c:v copy \
  -c:a aac -b:a 192k \
  -movflags +faststart "$remux_tmp/output.mp4"

output_duration="$(
  ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 \
    "$remux_tmp/output.mp4"
)"
if ! awk -v actual="$output_duration" -v expected="$video_duration" \
  'BEGIN { delta = actual - expected; if (delta < 0) delta = -delta; exit !(delta <= 0.05) }'; then
  printf 'narration-remux: unexpected duration %s, expected %s\n' \
    "$output_duration" "$video_duration" >&2
  exit 1
fi
delivery_audio_json="$(
  "$SCRIPT_DIR/verify_delivery_audio.sh" "$remux_tmp/output.mp4"
)"

video_sha="$(sha256sum "$remux_tmp/output.mp4" | awk '{print $1}')"
source_audio_sha="$(sha256sum "$source_audio" | awk '{print $1}')"
normalized_audio_sha="$(sha256sum "$audio" | awk '{print $1}')"
subtitles_sha="$(sha256sum "$subtitles" | awk '{print $1}')"
sound_design_sha="$(sha256sum "$sound_design" | awk '{print $1}')"
awk -F= \
  -v video_sha="$video_sha" \
  -v source_audio_sha="$source_audio_sha" \
  -v normalized_audio_sha="$normalized_audio_sha" \
  -v subtitles_sha="$subtitles_sha" \
  -v sound_design_sha="$sound_design_sha" \
  -v measured_i="$(jq -r '.measured_i' "$loudness_report")" \
  -v measured_tp="$(jq -r '.measured_tp' "$loudness_report")" \
  -v delivery_i="$(jq -r '.measured_i' <<<"$delivery_audio_json")" \
  -v delivery_tp="$(jq -r '.measured_tp' <<<"$delivery_audio_json")" '
  BEGIN { OFS = "=" }
  $1 == "video_sha256" { $2 = video_sha }
  $1 ~ /^audio_/ || $1 == "sound_design_sha256" || $1 == "subtitles_sha256" || $1 == "subtitle_text_exact" { next }
  { print }
  END {
    print "audio_source_sha256=" source_audio_sha
    print "audio_normalized_sha256=" normalized_audio_sha
    print "subtitles_sha256=" subtitles_sha
    print "sound_design_sha256=" sound_design_sha
    print "audio_mix=voice_plus_ducked_beat_sfx"
    print "audio_codec=aac"
    print "audio_standard=-16_LUFS_-1.5_dBTP_48kHz_mono_PCM24_source"
    print "audio_measured_i=" measured_i
    print "audio_measured_tp=" measured_tp
    print "audio_delivery_standard=-16_LUFS_plus_minus_1_-1.0_dBTP_max_48kHz_mono"
    print "audio_delivery_measured_i=" delivery_i
    print "audio_delivery_measured_tp=" delivery_tp
    print "subtitle_text_exact=true"
  }
  ' "$manifest" >"$remux_tmp/manifest.txt"

mv "$remux_tmp/output.mp4" "$video_abs"
mv "$remux_tmp/manifest.txt" "$manifest"
printf 'narration-remux: completed %s (%ss, standardized narration)\n' \
  "$video_abs" "$output_duration"
