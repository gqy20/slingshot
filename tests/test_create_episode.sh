#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/slingshot-create-episode.XXXXXX)"
cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

"$PROJECT_ROOT/scripts/create_episode.sh" framework-test \
  --template stretch \
  --season 2 \
  --episode 3 \
  --title "脚手架测试" \
  --output-root "$TEST_ROOT" >/dev/null

EPISODE="$TEST_ROOT/content/episodes/framework-test.json"
NARRATION="$TEST_ROOT/content/narration/framework-test.txt"
test -s "$EPISODE"
test -s "$NARRATION"
test "$(jq -r '.id' "$EPISODE")" = "framework-test"
test "$(jq -r '.season' "$EPISODE")" = "2"
test "$(jq -r '.episode' "$EPISODE")" = "3"
test "$(jq -r '.beat_template' "$EPISODE")" = "editorial_comparison_v1"
test "$(jq -r '.story.explanation.module' "$EPISODE")" = "spring_energy"
test "$(jq -r '.narration.script' "$EPISODE")" = "res://content/narration/framework-test.txt"

"$PROJECT_ROOT/scripts/validate_episode.sh" \
  "$PROJECT_ROOT/content/episodes/s01e01-angle-sweep.json" >/dev/null

if "$PROJECT_ROOT/scripts/create_episode.sh" framework-test \
  --output-root "$TEST_ROOT" >/dev/null 2>&1; then
  printf 'CREATE EPISODE TEST: overwrite guard failed\n' >&2
  exit 1
fi

printf 'CREATE EPISODE TEST: passed\n'
