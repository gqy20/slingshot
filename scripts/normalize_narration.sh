#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'usage: %s <episode.json>\n' "$0" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
for required_command in ffmpeg ffprobe jq realpath sha256sum awk; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    printf 'narration-normalize: missing command: %s\n' "$required_command" >&2
    exit 2
  fi
done

episode_abs="$(realpath "$1")"
stem="$(basename "${episode_abs%.json}")"
output_dir="$PROJECT_ROOT/renders/narration/$stem"
source_audio="$output_dir/narration.mp3"
normalized_audio="$output_dir/narration-normalized.wav"
report="$output_dir/narration-loudness.json"
if [[ ! -s "$source_audio" ]]; then
  printf 'narration-normalize: source audio missing: %s\n' "$source_audio" >&2
  exit 2
fi

source_sha="$(sha256sum "$source_audio" | awk '{print $1}')"
if [[ -s "$normalized_audio" && -s "$report" ]] \
  && [[ "$(jq -r '.source_sha256 // ""' "$report")" == "$source_sha" ]] \
  && [[ "$(jq -r '.target_i // 0' "$report")" == -16 ]] \
  && [[ "$(jq -r '.normalized_sha256 // ""' "$report")" \
    == "$(sha256sum "$normalized_audio" | awk '{print $1}')" ]]; then
  printf 'narration-normalize: cached %s I=%s LUFS TP=%s dBTP\n' \
    "$stem" "$(jq -r '.measured_i' "$report")" "$(jq -r '.measured_tp' "$report")"
  exit 0
fi

normalize_tmp="$(mktemp -d /tmp/slingshot-normalize.XXXXXX)"
cleanup() {
  rm -rf "$normalize_tmp"
}
trap cleanup EXIT

first_pass_log="$normalize_tmp/first-pass.log"
ffmpeg -hide_banner -nostats -i "$source_audio" \
  -af 'loudnorm=I=-16:TP=-1.5:LRA=7:print_format=json' \
  -f null - >"$normalize_tmp/first-pass.out" 2>"$first_pass_log"
first_pass_json="$(awk '
  /\[Parsed_loudnorm_/ { ready = 1 }
  ready && /^\{/ { capture = 1 }
  capture { print }
  capture && /^\}/ { exit }
' "$first_pass_log")"
if ! jq -e . >/dev/null 2>&1 <<<"$first_pass_json"; then
  printf 'narration-normalize: failed to parse first-pass measurement for %s\n' "$stem" >&2
  exit 1
fi

measured_i="$(jq -r '.input_i' <<<"$first_pass_json")"
measured_tp="$(jq -r '.input_tp' <<<"$first_pass_json")"
measured_lra="$(jq -r '.input_lra' <<<"$first_pass_json")"
measured_thresh="$(jq -r '.input_thresh' <<<"$first_pass_json")"
offset="$(jq -r '.target_offset' <<<"$first_pass_json")"
filter="loudnorm=I=-16:TP=-1.5:LRA=7:measured_I=$measured_i:measured_TP=$measured_tp:measured_LRA=$measured_lra:measured_thresh=$measured_thresh:offset=$offset:linear=true:print_format=json"

ffmpeg -y -loglevel error -i "$source_audio" \
  -af "$filter,aresample=48000" \
  -ar 48000 -ac 1 -c:a pcm_s24le "$normalize_tmp/narration-normalized.wav"

verify_log="$normalize_tmp/verify.log"
ffmpeg -hide_banner -nostats -i "$normalize_tmp/narration-normalized.wav" \
  -af 'loudnorm=I=-16:TP=-1.5:LRA=7:print_format=json' \
  -f null - >"$normalize_tmp/verify.out" 2>"$verify_log"
verify_json="$(awk '
  /\[Parsed_loudnorm_/ { ready = 1 }
  ready && /^\{/ { capture = 1 }
  capture { print }
  capture && /^\}/ { exit }
' "$verify_log")"
if ! jq -e . >/dev/null 2>&1 <<<"$verify_json"; then
  printf 'narration-normalize: failed to parse verification measurement for %s\n' "$stem" >&2
  exit 1
fi
final_i="$(jq -r '.input_i' <<<"$verify_json")"
final_tp="$(jq -r '.input_tp' <<<"$verify_json")"
if ! awk -v integrated="$final_i" -v peak="$final_tp" '
  BEGIN {
    delta = integrated + 16.0
    if (delta < 0) delta = -delta
    exit !(delta <= 1.0 && peak <= -1.4)
  }
'; then
  printf 'narration-normalize: verification failed for %s (I=%s TP=%s)\n' \
    "$stem" "$final_i" "$final_tp" >&2
  exit 1
fi

normalized_sha="$(sha256sum "$normalize_tmp/narration-normalized.wav" | awk '{print $1}')"
duration="$(
  ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 \
    "$normalize_tmp/narration-normalized.wav"
)"
jq -n \
  --arg source_sha256 "$source_sha" \
  --arg normalized_sha256 "$normalized_sha" \
  --arg duration_sec "$duration" \
  --arg measured_i "$final_i" \
  --arg measured_tp "$final_tp" \
  --arg measured_lra "$(jq -r '.input_lra' <<<"$verify_json")" \
  '{
    schema_version: 1,
    standard: "online_voice",
    target_i: -16,
    target_tp: -1.5,
    target_lra: 7,
    sample_rate_hz: 48000,
    channels: 1,
    codec: "pcm_s24le",
    source_sha256: $source_sha256,
    normalized_sha256: $normalized_sha256,
    duration_sec: ($duration_sec | tonumber),
    measured_i: ($measured_i | tonumber),
    measured_tp: ($measured_tp | tonumber),
    measured_lra: ($measured_lra | tonumber)
  }' >"$normalize_tmp/narration-loudness.json"

mv "$normalize_tmp/narration-normalized.wav" "$normalized_audio"
mv "$normalize_tmp/narration-loudness.json" "$report"
printf 'narration-normalize: completed %s I=%s LUFS TP=%s dBTP\n' \
  "$stem" "$final_i" "$final_tp"
