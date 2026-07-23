#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  printf 'usage: %s <episode.mp4> [contact-sheet.png]\n' "$0" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_DIR/render_paths.sh"

for required_command in ffmpeg ffprobe realpath sha256sum awk jq; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    printf 'episode-review: missing command: %s\n' "$required_command" >&2
    exit 2
  fi
done

VIDEO_ABS="$(realpath "$1")"
if [[ ! -f "$VIDEO_ABS" ]]; then
  printf 'episode-review: video not found: %s\n' "$VIDEO_ABS" >&2
  exit 2
fi

stem="$(basename "${VIDEO_ABS%.mp4}")"
if [[ $# -eq 2 ]]; then
  OUTPUT_INPUT="$2"
else
  OUTPUT_INPUT="$RENDER_CONTACT_SHEETS_DIR/$stem/${stem}--seven-beat.png"
fi
OUTPUT_DIR="$(dirname "$OUTPUT_INPUT")"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR_ABS="$(cd "$OUTPUT_DIR" && pwd)"
OUTPUT_PNG="$OUTPUT_DIR_ABS/$(basename "$OUTPUT_INPUT")"
OUTPUT_NOTES="${OUTPUT_PNG%.png}.txt"

duration="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$VIDEO_ABS")"
rate="$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of default=nw=1:nk=1 "$VIDEO_ABS")"
if [[ "$rate" != '30/1' && "$rate" != '60/1' ]]; then
  printf 'episode-review: expected 30/1 or 60/1 fps, got %s\n' "$rate" >&2
  exit 2
fi
fps="${rate%/1}"

MANIFEST="${VIDEO_ABS%.mp4}.manifest.txt"
EPISODE_JSON=""
if [[ -f "$MANIFEST" ]]; then
  episode_name="$(awk -F= '$1 == "episode" { print $2; exit }' "$MANIFEST")"
  if [[ -n "$episode_name" ]]; then
    episode_candidate="$PROJECT_ROOT/content/episodes/$(basename "$episode_name")"
    if [[ -f "$episode_candidate" ]]; then
      EPISODE_JSON="$episode_candidate"
    fi
  fi
fi
if [[ -z "$EPISODE_JSON" ]]; then
  episode_candidate="$PROJECT_ROOT/content/episodes/${stem}.json"
  if [[ -f "$episode_candidate" ]]; then
    EPISODE_JSON="$episode_candidate"
  fi
fi

if [[ -n "$EPISODE_JSON" ]] \
  && jq -e '.story | type == "object"' "$EPISODE_JSON" >/dev/null 2>&1; then
  read -r question_sec explain_sec setup_sec flight_sec compare_sec < <(
    jq -r '[
      .story.question_sec,
      (.story.explain_sec // 0),
      .story.setup_sec,
      .story.flight_sec,
      .story.compare_sec
    ] | @tsv' "$EPISODE_JSON"
  )
  readarray -t samples < <(
    awk \
      -v question="$question_sec" \
      -v explain="$explain_sec" \
      -v setup="$setup_sec" \
      -v flight="$flight_sec" \
      -v compare="$compare_sec" \
			-v fps="$fps" \
      'BEGIN {
        times[1] = question * 0.50
        times[2] = question + explain * 0.50
        times[3] = question + explain + setup * 0.50
        times[4] = question + explain + setup + flight * 0.05
        times[5] = question + explain + setup + flight * 0.50
        times[6] = question + explain + setup + flight * 0.85
        times[7] = question + explain + setup + flight + compare * 0.75
        labels[1] = "QUESTION"
        labels[2] = "EXPLAIN"
        labels[3] = "SETUP"
        labels[4] = "LAUNCH"
        labels[5] = "MID_FLIGHT"
        labels[6] = "LANDING"
        labels[7] = "COMPARE"
        for (i = 1; i <= 7; i++) {
          frame = int(times[i] * fps + 0.5)
          printf "%s\t%.3f\t%d\n", labels[i], times[i], frame
        }
      }'
  )
  sampling_source="episode-source"
else
  readarray -t samples < <(
		awk -v duration="$duration" -v fps="$fps" 'BEGIN {
      split("QUESTION:0.08 EXPLAIN:0.20 SETUP:0.34 LAUNCH:0.46 MID_FLIGHT:0.58 LANDING:0.70 COMPARE:0.90", items, " ")
      for (i = 1; i <= 7; i++) {
        split(items[i], fields, ":")
        time = duration * fields[2]
        frame = int(time * fps + 0.5)
        printf "%s\t%.3f\t%d\n", fields[1], time, frame
      }
    }'
  )
  sampling_source="duration-fallback"
fi

select_expr=""
for sample in "${samples[@]}"; do
  frame="${sample##*$'\t'}"
  if [[ -n "$select_expr" ]]; then
    select_expr+="+"
  fi
  select_expr+="eq(n,$frame)"
done

ffmpeg -y -loglevel error -i "$VIDEO_ABS" \
  -vf "select='$select_expr',scale=640:360,tile=4x2:padding=4:margin=4:color=#0E1116" \
  -frames:v 1 "$OUTPUT_PNG"

{
  printf 'video=%s\n' "$(basename "$VIDEO_ABS")"
  printf 'video_sha256=%s\n' "$(sha256sum "$VIDEO_ABS" | awk '{print $1}')"
  printf 'duration_sec=%s\n' "$duration"
  printf 'fps=%s\n' "$rate"
  printf 'sampling_source=%s\n' "$sampling_source"
  printf 'layout=4x2\n'
  printf 'order=left-to-right,top-to-bottom\n'
  for sample in "${samples[@]}"; do
    IFS=$'\t' read -r beat time frame <<<"$sample"
    printf '%s time_sec=%s frame=%s\n' "$beat" "$time" "$frame"
  done
} >"$OUTPUT_NOTES"

printf 'episode-review: contact-sheet %s\n' "$OUTPUT_PNG"
printf 'episode-review: notes %s\n' "$OUTPUT_NOTES"
