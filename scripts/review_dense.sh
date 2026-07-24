#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'usage: %s <episode.mp4>\n' "$0" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_DIR/render_paths.sh"

for required_command in ffmpeg ffprobe realpath sha256sum awk jq; do
  command -v "$required_command" >/dev/null 2>&1 || {
    printf 'dense-review: missing command: %s\n' "$required_command" >&2
    exit 2
  }
done

VIDEO_ABS="$(realpath "$1")"
if [[ ! -f "$VIDEO_ABS" || "$VIDEO_ABS" != *.mp4 ]]; then
  printf 'dense-review: video must be an existing MP4: %s\n' "$VIDEO_ABS" >&2
  exit 2
fi

stem="$(basename "${VIDEO_ABS%.mp4}")"
subject="$stem"
frames_root="${DENSE_REVIEW_FRAMES_DIR:-$RENDER_FRAMES_DIR}"
sheets_root="${DENSE_REVIEW_SHEETS_DIR:-$RENDER_CONTACT_SHEETS_DIR}"
output_dir="$frames_root/$subject/dense-2fps"
sheet_dir="$sheets_root/$subject/dense-2fps"

duration="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$VIDEO_ABS")"
rate="$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of default=nw=1:nk=1 "$VIDEO_ABS")"
if [[ "$rate" != '30/1' && "$rate" != '60/1' ]]; then
  printf 'dense-review: expected 30/1 or 60/1 fps, got %s\n' "$rate" >&2
  exit 2
fi
source_fps="${rate%/1}"
expected_count="$(awk -v duration="$duration" 'BEGIN { printf "%d", int(duration * 2 + 0.5) }')"
expected_pages=$(((expected_count + 23) / 24))

review_tmp="$(mktemp -d /tmp/slingshot-dense-review.XXXXXX)"
cleanup() {
  find "$review_tmp" -depth -delete
}
trap cleanup EXIT
mkdir -p "$review_tmp/frames" "$review_tmp/sheets"

ffmpeg -y -loglevel error -i "$VIDEO_ABS" \
  -vf 'fps=2' -start_number 0 "$review_tmp/frames/sample-%06d.png"

actual_count="$(find "$review_tmp/frames" -maxdepth 1 -name 'sample-*.png' -printf '.' | wc -c)"
if [[ "$actual_count" -ne "$expected_count" ]]; then
  printf 'dense-review: extracted %s frames, expected %s\n' "$actual_count" "$expected_count" >&2
  exit 1
fi

samples_tsv="$review_tmp/samples.tsv"
: >"$samples_tsv"
for ((sample_index = 0; sample_index < actual_count; sample_index += 1)); do
	printf -v source_name 'sample-%06d.png' "$sample_index"
	time_ms=$((sample_index * 500))
  printf -v time_ms_padded '%09d' "$time_ms"
  target_name="${subject}--${time_ms_padded}ms--sample.png"
  mv "$review_tmp/frames/$source_name" "$review_tmp/frames/$target_name"
	awk -v name="$target_name" -v sample_index="$sample_index" -v fps="$source_fps" \
		'BEGIN { printf "%s\t%.3f\t%d\n", name, sample_index / 2.0, int(sample_index * fps / 2.0 + 0.5) }' \
    >>"$samples_tsv"
done

episode_json=""
video_manifest="${VIDEO_ABS%.mp4}.manifest.txt"
if [[ -f "$video_manifest" ]]; then
  episode_name="$(awk -F= '$1 == "episode" { print $2; exit }' "$video_manifest")"
  episode_candidate="$PROJECT_ROOT/content/episodes/$(basename "$episode_name")"
  [[ -f "$episode_candidate" ]] && episode_json="$episode_candidate"
fi
if [[ -z "$episode_json" && -f "$PROJECT_ROOT/content/episodes/$subject.json" ]]; then
  episode_json="$PROJECT_ROOT/content/episodes/$subject.json"
fi

index_tsv="$review_tmp/index.tsv"
printf 'filename\ttime_sec\tsource_frame\tbeat_id\tmode\tcamera_action\tcamera_reason\tintent\tprimary_subject\n' >"$index_tsv"
if [[ -n "$episode_json" ]]; then
  jq -r '.beats[] | [.at, (.at + .duration), .id, .mode, .camera_action, .camera_reason, .intent, .primary_subject] | @tsv' \
    "$episode_json" >"$review_tmp/beats.tsv"
	awk -F '\t' 'BEGIN { OFS="\t"; beat_count = 0 }
		NR == FNR {
			start[beat_count] = $1; finish[beat_count] = $2; beat[beat_count] = $3;
			mode[beat_count] = $4; camera_action[beat_count] = $5;
			camera_reason[beat_count] = $6; intent[beat_count] = $7; subject[beat_count] = $8;
			beat_count += 1; next
		}
		{
			selected = beat_count - 1
			for (i = 0; i < beat_count; i += 1) {
        if ($2 >= start[i] && $2 < finish[i]) { selected = i; break }
      }
      print $1, $2, $3, beat[selected], mode[selected], camera_action[selected], camera_reason[selected], intent[selected], subject[selected]
		}' "$review_tmp/beats.tsv" "$samples_tsv" >>"$index_tsv"
	expected_beats="$(jq '.beats | length' "$episode_json")"
	indexed_beats="$(awk -F '\t' 'NR > 1 { print $4 }' "$index_tsv" | sort -u | wc -l)"
	if [[ "$indexed_beats" -ne "$expected_beats" ]]; then
		printf 'dense-review: index covers %s beats, expected %s\n' \
			"$indexed_beats" "$expected_beats" >&2
		exit 1
	fi
else
  awk -F '\t' 'BEGIN { OFS="\t" } { print $1, $2, $3, "", "", "", "", "", "" }' \
    "$samples_tsv" >>"$index_tsv"
fi

ffmpeg -y -loglevel error -i "$VIDEO_ABS" \
  -vf 'fps=2,scale=320:180,tile=4x6:padding=4:margin=4:color=#0E1116' \
  -vsync 0 -start_number 1 "$review_tmp/sheets/page-%02d.png"
actual_pages="$(find "$review_tmp/sheets" -maxdepth 1 -name 'page-*.png' -printf '.' | wc -c)"
if [[ "$actual_pages" -ne "$expected_pages" ]]; then
  printf 'dense-review: produced %s contact pages, expected %s\n' "$actual_pages" "$expected_pages" >&2
  exit 1
fi

manifest="$review_tmp/dense-2fps.manifest.txt"
{
  printf 'video=%s\n' "$(basename "$VIDEO_ABS")"
  printf 'video_sha256=%s\n' "$(sha256sum "$VIDEO_ABS" | awk '{print $1}')"
  printf 'duration_sec=%s\n' "$duration"
  printf 'source_fps=%s\n' "$rate"
  printf 'sample_fps=2\n'
  printf 'sample_interval_ms=500\n'
  printf 'sample_count=%s\n' "$actual_count"
  printf 'contact_sheet_pages=%s\n' "$actual_pages"
  printf 'contact_sheet_layout=4x6\n'
  [[ -n "$episode_json" ]] && printf 'episode=%s\n' "$(basename "$episode_json")"
} >"$manifest"

mkdir -p "$output_dir" "$sheet_dir"
find "$output_dir" -maxdepth 1 -type f -delete
find "$sheet_dir" -maxdepth 1 -type f -delete
mv "$review_tmp/frames"/*.png "$output_dir/"
mv "$index_tsv" "$manifest" "$output_dir/"
page_index=1
while IFS= read -r page; do
  printf -v page_name '%s--dense-2fps--page-%02d.png' "$subject" "$page_index"
  mv "$page" "$sheet_dir/$page_name"
  page_index=$((page_index + 1))
done < <(find "$review_tmp/sheets" -maxdepth 1 -name 'page-*.png' -print | sort)

printf 'dense-review: frames=%s output=%s\n' "$actual_count" "$output_dir"
printf 'dense-review: pages=%s output=%s\n' "$actual_pages" "$sheet_dir"
