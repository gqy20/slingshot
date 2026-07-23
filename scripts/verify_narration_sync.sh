#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'usage: %s <episode.json>\n' "$0" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_DIR/render_paths.sh"
for required_command in jq realpath awk tr sha256sum; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    printf 'narration-sync: missing command: %s\n' "$required_command" >&2
    exit 2
  fi
done

episode_abs="$(realpath "$1")"
stem="$(basename "${episode_abs%.json}")"
script_value="$(jq -er '.narration.script' "$episode_abs")"
if [[ "$script_value" != res://* ]]; then
  printf 'narration-sync: script must use res:// path: %s\n' "$script_value" >&2
  exit 2
fi
narration_script="$PROJECT_ROOT/${script_value#res://}"
subtitles="$RENDER_NARRATION_DIR/$stem/narration.srt"
if [[ ! -s "$narration_script" || ! -s "$subtitles" ]]; then
  printf 'narration-sync: script or subtitles missing for %s\n' "$stem" >&2
  exit 2
fi

script_text="$(tr -d '[:space:]' <"$narration_script")"
subtitle_text="$(
  awk '
    !/^[0-9]+$/ && !/-->/ && NF {
      gsub(/[[:space:]\r]/, "")
      printf "%s", $0
    }
  ' "$subtitles"
)"
if [[ -z "$script_text" || "$script_text" != "$subtitle_text" ]]; then
  printf 'narration-sync: SRT text does not exactly match script for %s\n' "$stem" >&2
  printf 'narration-sync: script_chars=%s subtitle_chars=%s\n' \
    "${#script_text}" "${#subtitle_text}" >&2
  exit 1
fi

canonical_sha="$(printf '%s' "$script_text" | sha256sum | awk '{print $1}')"
printf 'narration-sync: %s exact chars=%s canonical_sha256=%s\n' \
  "$stem" "${#script_text}" "$canonical_sha"
