#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  printf 'usage: %s <episode.json> [episode.mp4]\n' "$0" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
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
  video_abs="$PROJECT_ROOT/renders/episodes/$stem.mp4"
fi
audio="$PROJECT_ROOT/renders/narration/$stem/narration.mp3"
subtitles="$PROJECT_ROOT/renders/narration/$stem/narration.srt"
manifest="${video_abs%.mp4}.manifest.txt"
for required_file in "$episode_abs" "$video_abs" "$audio" "$subtitles" "$manifest"; do
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
  -i "$video_abs" -i "$audio" \
  -map 0:v:0 -map 1:a:0 \
  -t "$video_duration" \
  -c:v copy \
  -c:a aac -b:a 160k \
  -af 'loudnorm=I=-16:TP=-1.5:LRA=7,aresample=48000' \
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

video_sha="$(sha256sum "$remux_tmp/output.mp4" | awk '{print $1}')"
audio_sha="$(sha256sum "$audio" | awk '{print $1}')"
subtitles_sha="$(sha256sum "$subtitles" | awk '{print $1}')"
awk -F= \
  -v video_sha="$video_sha" \
  -v audio_sha="$audio_sha" \
  -v subtitles_sha="$subtitles_sha" '
  BEGIN { OFS = "=" }
  $1 == "video_sha256" { $2 = video_sha }
  $1 == "audio_sha256" { $2 = audio_sha }
  $1 == "subtitles_sha256" { $2 = subtitles_sha }
  $1 == "audio_loudness_target" { found_loudness = 1; $2 = "-16_LUFS" }
  { print }
  END { if (!found_loudness) print "audio_loudness_target=-16_LUFS" }
  ' "$manifest" >"$remux_tmp/manifest.txt"

mv "$remux_tmp/output.mp4" "$video_abs"
mv "$remux_tmp/manifest.txt" "$manifest"
printf 'narration-remux: completed %s (%ss, -16 LUFS target)\n' \
  "$video_abs" "$output_duration"
