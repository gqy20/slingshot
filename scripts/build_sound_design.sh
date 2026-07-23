#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'usage: %s <episode.json>\n' "$0" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_DIR/render_paths.sh"
for required_command in ffmpeg ffprobe jq realpath sha256sum awk; do
  command -v "$required_command" >/dev/null 2>&1 || {
    printf 'sound-design: missing command: %s\n' "$required_command" >&2
    exit 2
  }
done

episode_abs="$(realpath "$1")"
stem="$(basename "${episode_abs%.json}")"
output_dir="$RENDER_AUDIO_DIR/$stem"
output_audio="$output_dir/sound-design.wav"
output_manifest="$output_dir/sound-design.manifest.txt"
duration="$(jq -r '[.story.question_sec, (.story.explain_sec // 0), .story.setup_sec, .story.flight_sec, .story.compare_sec] | add' "$episode_abs")"
mkdir -p "$output_dir"

sound_tmp="$(mktemp -d /tmp/slingshot-sound.XXXXXX)"
cleanup() {
  find "$sound_tmp" -depth -delete
}
trap cleanup EXIT

filter_graph="anullsrc=r=48000:cl=mono:d=${duration}[base]"
mix_inputs="[base]"
cue_index=0
while IFS=$'\t' read -r cue_at cue_name; do
  [[ -n "$cue_name" ]] || continue
  delay_ms="$(awk -v seconds="$cue_at" 'BEGIN { printf "%d", seconds * 1000 + 0.5 }')"
  cue_label="cue${cue_index}"
  case "$cue_name" in
    cold-open)
      filter_graph+=";sine=f=330:r=48000:d=0.62,volume=0.10,tremolo=f=7:d=0.55,afade=t=out:st=0.28:d=0.34,adelay=${delay_ms}:all=1[${cue_label}]"
      ;;
    release)
      filter_graph+=";anoisesrc=color=pink:r=48000:d=0.72:a=0.10,highpass=f=420,lowpass=f=6200,afade=t=in:st=0:d=0.03,afade=t=out:st=0.18:d=0.54,adelay=${delay_ms}:all=1[${cue_label}]"
      ;;
    landing)
      filter_graph+=";anoisesrc=color=brown:r=48000:d=0.42:a=0.13,highpass=f=70,lowpass=f=900,afade=t=out:st=0.06:d=0.36,adelay=${delay_ms}:all=1[${cue_label}]"
      ;;
    result)
      filter_graph+=";sine=f=660:r=48000:d=0.78,volume=0.075,tremolo=f=5:d=0.65,afade=t=out:st=0.34:d=0.44,adelay=${delay_ms}:all=1[${cue_label}]"
      ;;
    *)
      printf 'sound-design: unsupported cue: %s\n' "$cue_name" >&2
      exit 2
      ;;
  esac
  mix_inputs+="[${cue_label}]"
  cue_index=$((cue_index + 1))
done < <(jq -r '.beats[] | select((.sfx // "") != "") | [.at, .sfx] | @tsv' "$episode_abs")

filter_graph+=";${mix_inputs}amix=inputs=$((cue_index + 1)):duration=longest:normalize=0,alimiter=limit=0.35[out]"
ffmpeg -y -loglevel error -filter_complex "$filter_graph" -map '[out]' \
  -t "$duration" -ar 48000 -ac 1 -c:a pcm_s24le "$sound_tmp/sound-design.wav"

actual_duration="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$sound_tmp/sound-design.wav")"
if ! awk -v actual="$actual_duration" -v expected="$duration" 'BEGIN { delta=actual-expected; if (delta<0) delta=-delta; exit !(delta<=0.01) }'; then
  printf 'sound-design: unexpected duration %s, expected %s\n' "$actual_duration" "$duration" >&2
  exit 1
fi

{
  printf 'episode=%s\n' "$(basename "$episode_abs")"
  printf 'episode_sha256=%s\n' "$(sha256sum "$episode_abs" | awk '{print $1}')"
  printf 'sound_design_sha256=%s\n' "$(sha256sum "$sound_tmp/sound-design.wav" | awk '{print $1}')"
  printf 'cue_count=%s\n' "$cue_index"
  printf 'duration_sec=%s\n' "$actual_duration"
  printf 'sample_rate_hz=48000\nchannels=1\ncodec=pcm_s24le\n'
} >"$sound_tmp/sound-design.manifest.txt"

mv "$sound_tmp/sound-design.wav" "$output_audio"
mv "$sound_tmp/sound-design.manifest.txt" "$output_manifest"
printf 'sound-design: %s cues=%s duration=%ss\n' "$stem" "$cue_index" "$actual_duration"
