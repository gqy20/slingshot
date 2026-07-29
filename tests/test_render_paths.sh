#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/.." && pwd)"
. "$PROJECT_ROOT/scripts/render_paths.sh"

test "$RENDER_ROOT" = "$PROJECT_ROOT/renders"
test "$RENDER_WORK_DIR" = "$PROJECT_ROOT/renders/work"
test "$RENDER_MASTERS_DIR" = "$PROJECT_ROOT/renders/masters"
test "$RENDER_DELIVERIES_DIR" = "$PROJECT_ROOT/renders/deliveries"
test "$RENDER_ARCHIVE_DIR" = "$PROJECT_ROOT/renders/archive"
test "$RENDER_CACHE_DIR" = "$PROJECT_ROOT/renders/cache"
test "$(episode_preview_dir s01e04-impact-force-curve)" = \
  "$PROJECT_ROOT/renders/work/s01e04-impact-force-curve/previews"
test "$(episode_audio_dir s01e04-impact-force-curve)" = \
  "$PROJECT_ROOT/renders/masters/s01e04-impact-force-curve/audio"
test -f "$RENDER_ROOT/.gdignore"
test -f "$RENDER_ROOT/README.md"

for script in "$PROJECT_ROOT"/scripts/*.sh; do
  bash -n "$script"
done

one_job_plan="$(
  EPISODE_RENDER_WORKERS=2 RENDER_DRY_RUN=1 "$PROJECT_ROOT/scripts/render_batch.sh" --jobs 1 \
    "$PROJECT_ROOT/content/episodes/s01e01-angle-sweep.json"
)"
case "$one_job_plan" in
  *'jobs=1 episode-workers=2 total-worker-limit=4'*) ;;
  *) printf 'unexpected one-job render plan: %s\n' "$one_job_plan" >&2; exit 1 ;;
esac

two_job_plan="$(
  EPISODE_RENDER_WORKERS=2 RENDER_DRY_RUN=1 "$PROJECT_ROOT/scripts/render_batch.sh" --jobs 2 \
    "$PROJECT_ROOT/content/episodes/s01e01-angle-sweep.json" \
    "$PROJECT_ROOT/content/episodes/s01e02-stretch-sweep.json"
)"
case "$two_job_plan" in
  *'jobs=2 episode-workers=2 total-worker-limit=4'*) ;;
  *) printf 'unexpected two-job render plan: %s\n' "$two_job_plan" >&2; exit 1 ;;
esac

preview_plan="$(
  EPISODE_RENDER_WIDTH=1920 EPISODE_RENDER_HEIGHT=1080 EPISODE_RENDER_WORKERS=2 RENDER_DRY_RUN=1 \
    "$PROJECT_ROOT/scripts/render_batch.sh" --jobs 2 \
    "$PROJECT_ROOT/content/episodes/s01e01-angle-sweep.json" \
    "$PROJECT_ROOT/content/episodes/s01e02-stretch-sweep.json"
)"
case "$preview_plan" in
  *"output=<episode-scoped-defaults> suffix=<none>"*) ;;
  *) printf 'unexpected preview output plan: %s\n' "$preview_plan" >&2; exit 1 ;;
esac

if RENDER_DRY_RUN=1 "$PROJECT_ROOT/scripts/render_batch.sh" --jobs 5 \
  "$PROJECT_ROOT/content/episodes/s01e01-angle-sweep.json" >/dev/null 2>&1; then
  printf 'batch render accepted jobs above the total worker limit\n' >&2
  exit 1
fi

printf 'RENDER PATHS TEST: passed\n'
