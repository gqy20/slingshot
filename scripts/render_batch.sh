#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_DIR/render_paths.sh"
JOBS="${RENDER_JOBS:-1}"
MAX_TOTAL_WORKERS="${RENDER_MAX_WORKERS:-4}"
REQUESTED_EPISODE_WORKERS="${EPISODE_RENDER_WORKERS:-2}"
DRY_RUN="${RENDER_DRY_RUN:-0}"
OUTPUT_DIR=""
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
if [[ ! "$MAX_TOTAL_WORKERS" =~ ^[1-9][0-9]*$ ]]; then
  printf 'batch-render: RENDER_MAX_WORKERS must be a positive integer\n' >&2
  exit 2
fi
if [[ ! "$REQUESTED_EPISODE_WORKERS" =~ ^[1-9][0-9]*$ ]]; then
  printf 'batch-render: EPISODE_RENDER_WORKERS must be a positive integer\n' >&2
  exit 2
fi
if [[ "$DRY_RUN" != 0 && "$DRY_RUN" != 1 ]]; then
  printf 'batch-render: RENDER_DRY_RUN must be 0 or 1\n' >&2
  exit 2
fi
if [[ "$JOBS" -gt "$MAX_TOTAL_WORKERS" ]]; then
  printf 'batch-render: jobs=%s exceeds total worker limit=%s\n' \
    "$JOBS" "$MAX_TOTAL_WORKERS" >&2
  exit 2
fi
workers_per_episode=$((MAX_TOTAL_WORKERS / JOBS))
if [[ "$workers_per_episode" -gt "$REQUESTED_EPISODE_WORKERS" ]]; then
  workers_per_episode="$REQUESTED_EPISODE_WORKERS"
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

OUTPUT_SUFFIX=""
if [[ "${EPISODE_RENDER_WIDTH:-}" == 1920 && "${EPISODE_RENDER_HEIGHT:-}" == 1080 ]]; then
  OUTPUT_SUFFIX="--1080p-preview"
  if [[ -z "$OUTPUT_DIR" ]]; then
    OUTPUT_DIR="$RENDER_PREVIEWS_DIR"
  fi
elif [[ -z "$OUTPUT_DIR" ]]; then
  OUTPUT_DIR="$RENDER_FINAL_DIR"
fi

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR_ABS="$(cd "$OUTPUT_DIR" && pwd)"

for episode in "${EPISODES[@]}"; do
  if [[ ! -f "$episode" ]]; then
    printf 'batch-render: episode not found: %s\n' "$episode" >&2
    exit 2
  fi
done

printf 'batch-render: jobs=%s episode-workers=%s total-worker-limit=%s episodes=%s output=%s suffix=%s\n' \
  "$JOBS" "$workers_per_episode" "$MAX_TOTAL_WORKERS" \
  "${#EPISODES[@]}" "$OUTPUT_DIR_ABS" "${OUTPUT_SUFFIX:-<none>}"
if [[ "$DRY_RUN" == 1 ]]; then
  printf 'batch-render: dry-run; no render processes started\n'
  exit 0
fi

export SLINGSHOT_RENDER_SCRIPT="$SCRIPT_DIR/render_episode.sh"
export SLINGSHOT_OUTPUT_DIR="$OUTPUT_DIR_ABS"
export SLINGSHOT_OUTPUT_SUFFIX="$OUTPUT_SUFFIX"
export EPISODE_RENDER_WORKERS="$workers_per_episode"
printf '%s\0' "${EPISODES[@]}" |
  xargs -0 -P "$JOBS" -n 1 bash -c '
    set -euo pipefail
    episode="$1"
    stem="$(basename "${episode%.json}")"
    "$SLINGSHOT_RENDER_SCRIPT" "$episode" \
      "$SLINGSHOT_OUTPUT_DIR/$stem$SLINGSHOT_OUTPUT_SUFFIX.mp4"
  ' _

printf 'batch-render: completed %s episode(s) with jobs=%s\n' \
  "${#EPISODES[@]}" "$JOBS"
