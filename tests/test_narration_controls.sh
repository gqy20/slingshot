#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/.." && pwd)"
. "$PROJECT_ROOT/scripts/narration_text.sh"

for script_path in "$PROJECT_ROOT"/content/narration/s01e*.txt; do
  validate_speech_controls "$script_path"
  canonical="$(canonical_speech_text <"$script_path")"
  [[ -n "$canonical" && "$canonical" != *'<#'* ]]
done

control_tmp="$(mktemp -d /tmp/slingshot-speech-controls.XXXXXX)"
cleanup() {
  find "$control_tmp" -depth -delete
}
trap cleanup EXIT
printf '前文。<#0.35#>后文。\n' >"$control_tmp/valid.txt"
validate_speech_controls "$control_tmp/valid.txt"
test "$(canonical_speech_text <"$control_tmp/valid.txt")" = '前文。后文。'
printf '前文。<#0.123#>后文。\n' >"$control_tmp/invalid.txt"
if validate_speech_controls "$control_tmp/invalid.txt" >/dev/null 2>&1; then
  printf 'speech controls accepted a pause with too many decimal places\n' >&2
  exit 1
fi

printf 'NARRATION CONTROLS TEST: passed\n'
