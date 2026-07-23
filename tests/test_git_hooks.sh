#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/.." && pwd)"
HOOK="$PROJECT_ROOT/.githooks/commit-msg"
test_tmp="$(mktemp -d /tmp/slingshot-hooks.XXXXXX)"
cleanup() {
  find "$test_tmp" -depth -delete
}
trap cleanup EXIT

printf 'feat(audio): add timed speech controls\n' >"$test_tmp/valid"
"$HOOK" "$test_tmp/valid"

printf 'updated some files\n' >"$test_tmp/invalid"
if "$HOOK" "$test_tmp/invalid" >/dev/null 2>&1; then
  printf 'commit hook accepted a non-conventional subject\n' >&2
  exit 1
fi

printf 'GIT HOOKS TEST: passed\n'
