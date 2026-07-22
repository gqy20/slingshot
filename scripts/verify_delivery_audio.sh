#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'usage: %s <media-file>\n' "$0" >&2
  exit 2
fi

for required_command in ffmpeg ffprobe jq awk; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    printf 'delivery-audio: missing command: %s\n' "$required_command" >&2
    exit 2
  fi
done

media="$1"
if [[ ! -s "$media" ]]; then
  printf 'delivery-audio: media missing: %s\n' "$media" >&2
  exit 2
fi

audio_probe="$(
  ffprobe -v error -select_streams a:0 \
    -show_entries stream=codec_name,sample_rate,channels \
    -of json "$media"
)"
if [[ "$(jq -r '.streams | length' <<<"$audio_probe")" != 1 ]]; then
  printf 'delivery-audio: expected exactly one audio stream: %s\n' "$media" >&2
  exit 1
fi
codec="$(jq -r '.streams[0].codec_name' <<<"$audio_probe")"
sample_rate="$(jq -r '.streams[0].sample_rate' <<<"$audio_probe")"
channels="$(jq -r '.streams[0].channels' <<<"$audio_probe")"
if [[ "$sample_rate,$channels" != '48000,1' ]]; then
  printf 'delivery-audio: expected 48 kHz mono, got %s Hz/%s channels\n' \
    "$sample_rate" "$channels" >&2
  exit 1
fi

measure_tmp="$(mktemp -d /tmp/slingshot-delivery-audio.XXXXXX)"
cleanup() {
  rm -rf "$measure_tmp"
}
trap cleanup EXIT

ffmpeg -hide_banner -nostats -i "$media" -map 0:a:0 \
  -af 'loudnorm=I=-16:TP=-1.0:LRA=7:print_format=json' \
  -f null - >"$measure_tmp/measure.out" 2>"$measure_tmp/measure.log"
measurement="$(awk '
  /\[Parsed_loudnorm_/ { ready = 1 }
  ready && /^\{/ { capture = 1 }
  capture { print }
  capture && /^\}/ { exit }
' "$measure_tmp/measure.log")"
if ! jq -e . >/dev/null 2>&1 <<<"$measurement"; then
  printf 'delivery-audio: failed to parse loudness measurement: %s\n' "$media" >&2
  exit 1
fi

measured_i="$(jq -r '.input_i' <<<"$measurement")"
measured_tp="$(jq -r '.input_tp' <<<"$measurement")"
measured_lra="$(jq -r '.input_lra' <<<"$measurement")"
if ! awk -v integrated="$measured_i" -v peak="$measured_tp" '
  BEGIN {
    delta = integrated + 16.0
    if (delta < 0) delta = -delta
    exit !(delta <= 1.0 && peak <= -1.0)
  }
'; then
  printf 'delivery-audio: verification failed for %s (I=%s LUFS, TP=%s dBTP)\n' \
    "$media" "$measured_i" "$measured_tp" >&2
  exit 1
fi

jq -cn \
  --arg codec "$codec" \
  --argjson sample_rate_hz "$sample_rate" \
  --argjson channels "$channels" \
  --arg measured_i "$measured_i" \
  --arg measured_tp "$measured_tp" \
  --arg measured_lra "$measured_lra" \
  '{
    codec: $codec,
    sample_rate_hz: $sample_rate_hz,
    channels: $channels,
    target_i: -16,
    max_tp: -1.0,
    measured_i: ($measured_i | tonumber),
    measured_tp: ($measured_tp | tonumber),
    measured_lra: ($measured_lra | tonumber)
  }'
printf 'delivery-audio: verified %s I=%s LUFS TP=%s dBTP\n' \
  "$media" "$measured_i" "$measured_tp" >&2
