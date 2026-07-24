#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  printf 'usage: %s <episode-id> [--template angle|stretch] [--season N] [--episode N] [--title TEXT] [--output-root DIR]\n' "$0" >&2
}

if [[ $# -lt 1 ]]; then
  usage
  exit 2
fi

episode_id="$1"
shift
template_name="angle"
season="1"
episode_number="0"
title=""
output_root="$PROJECT_ROOT"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --template)
      template_name="${2:-}"
      shift 2
      ;;
    --season)
      season="${2:-}"
      shift 2
      ;;
    --episode)
      episode_number="${2:-}"
      shift 2
      ;;
    --title)
      title="${2:-}"
      shift 2
      ;;
    --output-root)
      output_root="${2:-}"
      shift 2
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if [[ ! "$episode_id" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  printf 'create-episode: id must use lowercase letters, numbers, and hyphens\n' >&2
  exit 2
fi
if [[ ! "$season" =~ ^[0-9]+$ || ! "$episode_number" =~ ^[0-9]+$ ]]; then
  printf 'create-episode: season and episode must be non-negative integers\n' >&2
  exit 2
fi
case "$template_name" in
  angle)
    template_file="$PROJECT_ROOT/templates/episodes/angle-comparison.json"
    default_title="哪个角度飞得更远？"
    ;;
  stretch)
    template_file="$PROJECT_ROOT/templates/episodes/stretch-comparison.json"
    default_title="拉得更长会飞多远？"
    ;;
  *)
    printf 'create-episode: template must be angle or stretch\n' >&2
    exit 2
    ;;
esac
if [[ -z "$title" ]]; then
  title="$default_title"
fi
if ! command -v jq >/dev/null 2>&1; then
  printf 'create-episode: missing command: jq\n' >&2
  exit 2
fi

episode_dir="$output_root/content/episodes"
narration_dir="$output_root/content/narration"
episode_file="$episode_dir/$episode_id.json"
narration_file="$narration_dir/$episode_id.txt"
if [[ -e "$episode_file" || -e "$narration_file" ]]; then
  printf 'create-episode: refusing to overwrite existing episode files for %s\n' "$episode_id" >&2
  exit 1
fi
mkdir -p "$episode_dir" "$narration_dir"

episode_tmp="$(mktemp "$episode_dir/.${episode_id}.json.XXXXXX")"
narration_tmp="$(mktemp "$narration_dir/.${episode_id}.txt.XXXXXX")"
cleanup() {
  rm -f "$episode_tmp" "$narration_tmp"
}
trap cleanup EXIT

jq \
  --arg id "$episode_id" \
  --arg title "$title" \
  --argjson season "$season" \
  --argjson episode "$episode_number" \
  '.id = $id
   | .title = $title
   | .season = $season
   | .episode = $episode
   | .narration.script = ("res://content/narration/" + $id + ".txt")
   | .story.explanation.asset_dir = ("res://assets/generated/formulas/" + $id)' \
  "$template_file" >"$episode_tmp"
printf '%s。<#0.5#>请把这里替换为完整讲稿，并让每句话都像在和观众一起讨论问题。\n' \
  "$title" >"$narration_tmp"

mv "$episode_tmp" "$episode_file"
mv "$narration_tmp" "$narration_file"
trap - EXIT

printf 'create-episode: created %s\n' "$episode_file"
printf 'create-episode: created %s\n' "$narration_file"
if [[ "$(cd "$output_root" && pwd)" == "$PROJECT_ROOT" ]]; then
  "$SCRIPT_DIR/validate_episode.sh" "$episode_file"
fi
printf 'create-episode: next edit story, beat_overrides, variants, and narration; then run scripts/render_episode.sh %s\n' "$episode_file"
