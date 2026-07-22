#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
JOBS="${RENDER_JOBS:-2}"
OUTPUT_DIR="$PROJECT_ROOT/renders/episodes"
EPISODES=()

usage() {
  printf 'usage: %s [--jobs N] [--output-dir DIR] [episode.json ...]\n' "$0" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --jobs)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      JOBS="$2"
      shift 2
      ;;
    --output-dir)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --*)
      printf 'batch-render: unknown option: %s\n' "$1" >&2
      usage
      exit 2
      ;;
    *)
      EPISODES+=("$1")
      shift
      ;;
  esac
done

if [[ ! "$JOBS" =~ ^[1-9][0-9]*$ ]]; then
  printf 'batch-render: jobs must be a positive integer\n' >&2
  exit 2
fi

if [[ "${#EPISODES[@]}" -eq 0 ]]; then
  while IFS= read -r -d '' path; do
    EPISODES+=("$path")
  done < <(
    find "$PROJECT_ROOT/content/episodes" -maxdepth 1 -type f \
      -name 's[0-9][0-9]e[0-9][0-9]-*.json' -print0 | sort -z
  )
fi
if [[ "${#EPISODES[@]}" -eq 0 ]]; then
  printf 'batch-render: no production episodes found\n' >&2
  exit 2
fi

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR_ABS="$(cd "$OUTPUT_DIR" && pwd)"

for episode in "${EPISODES[@]}"; do
  if [[ ! -f "$episode" ]]; then
    printf 'batch-render: episode not found: %s\n' "$episode" >&2
    exit 2
  fi
done

printf 'batch-render: jobs=%s episodes=%s output=%s\n' \
  "$JOBS" "${#EPISODES[@]}" "$OUTPUT_DIR_ABS"

export SLINGSHOT_RENDER_SCRIPT="$SCRIPT_DIR/render_episode.sh"
export SLINGSHOT_OUTPUT_DIR="$OUTPUT_DIR_ABS"
printf '%s\0' "${EPISODES[@]}" |
  xargs -0 -P "$JOBS" -n 1 bash -c '
    set -euo pipefail
    episode="$1"
    stem="$(basename "${episode%.json}")"
    "$SLINGSHOT_RENDER_SCRIPT" "$episode" "$SLINGSHOT_OUTPUT_DIR/$stem.mp4"
  ' _

printf 'batch-render: completed %s episode(s) with jobs=%s\n' \
  "${#EPISODES[@]}" "$JOBS"
