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
test -f "$RENDER_ROOT/.gdignore"
test -f "$RENDER_ROOT/README.md"

for script in "$PROJECT_ROOT"/scripts/*.sh; do
  bash -n "$script"
done

printf 'RENDER PATHS TEST: passed\n'
