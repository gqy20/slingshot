#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/.." && pwd)"
. "$PROJECT_ROOT/scripts/render_paths.sh"

test "$RENDER_ROOT" = "$PROJECT_ROOT/renders"
test "$RENDER_FINAL_DIR" = "$PROJECT_ROOT/renders/final"
test "$RENDER_FRAMES_DIR" = "$PROJECT_ROOT/renders/frames"
test "$RENDER_CONTACT_SHEETS_DIR" = "$PROJECT_ROOT/renders/contact-sheets"
test "$RENDER_PREVIEWS_DIR" = "$PROJECT_ROOT/renders/previews"
test "$RENDER_SMOKE_DIR" = "$PROJECT_ROOT/renders/smoke"
test "$RENDER_NARRATION_DIR" = "$PROJECT_ROOT/renders/narration"
test "$RENDER_AUDIO_DIR" = "$PROJECT_ROOT/renders/audio"
test -f "$RENDER_ROOT/.gdignore"
test -f "$RENDER_ROOT/README.md"

for script in "$PROJECT_ROOT"/scripts/*.sh; do
  bash -n "$script"
done

one_job_plan="$(
  RENDER_DRY_RUN=1 "$PROJECT_ROOT/scripts/render_batch.sh" --jobs 1 \
    "$PROJECT_ROOT/content/episodes/s01e01-angle-sweep.json"
)"
case "$one_job_plan" in
  *'jobs=1 episode-workers=2 total-worker-limit=4'*) ;;
  *) printf 'unexpected one-job render plan: %s\n' "$one_job_plan" >&2; exit 1 ;;
esac

two_job_plan="$(
  RENDER_DRY_RUN=1 "$PROJECT_ROOT/scripts/render_batch.sh" --jobs 2 \
    "$PROJECT_ROOT/content/episodes/s01e01-angle-sweep.json" \
    "$PROJECT_ROOT/content/episodes/s01e02-stretch-sweep.json"
)"
case "$two_job_plan" in
  *'jobs=2 episode-workers=2 total-worker-limit=4'*) ;;
  *) printf 'unexpected two-job render plan: %s\n' "$two_job_plan" >&2; exit 1 ;;
esac

preview_plan="$(
  EPISODE_RENDER_WIDTH=1920 EPISODE_RENDER_HEIGHT=1080 RENDER_DRY_RUN=1 \
    "$PROJECT_ROOT/scripts/render_batch.sh" --jobs 2 \
    "$PROJECT_ROOT/content/episodes/s01e01-angle-sweep.json" \
    "$PROJECT_ROOT/content/episodes/s01e02-stretch-sweep.json"
)"
case "$preview_plan" in
  *"output=$RENDER_PREVIEWS_DIR suffix=--1080p-preview"*) ;;
  *) printf 'unexpected preview output plan: %s\n' "$preview_plan" >&2; exit 1 ;;
esac

if RENDER_DRY_RUN=1 "$PROJECT_ROOT/scripts/render_batch.sh" --jobs 5 \
  "$PROJECT_ROOT/content/episodes/s01e01-angle-sweep.json" >/dev/null 2>&1; then
  printf 'batch render accepted jobs above the total worker limit\n' >&2
  exit 1
fi

printf 'RENDER PATHS TEST: passed\n'
