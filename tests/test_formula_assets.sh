#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/.." && pwd)"

"$PROJECT_ROOT/scripts/build_formula_assets.sh" \
  "$PROJECT_ROOT/content/episodes/s01e01-angle-sweep.json" \
  "$PROJECT_ROOT/content/episodes/s01e02-stretch-sweep.json" >/dev/null
"$PROJECT_ROOT/scripts/build_formula_assets.sh" --check \
  "$PROJECT_ROOT/content/episodes/s01e01-angle-sweep.json" \
  "$PROJECT_ROOT/content/episodes/s01e02-stretch-sweep.json" >/dev/null

asset_count=0
while IFS= read -r -d '' formula_svg; do
  asset_count=$((asset_count + 1))
  grep -Fq 'viewBox="0 0 1800 192"' "$formula_svg"
  if grep -q '<text' "$formula_svg"; then
    printf 'formula asset contains non-portable text nodes: %s\n' "$formula_svg" >&2
    exit 1
  fi
done < <(
  find "$PROJECT_ROOT/assets/generated/formulas" -type f -name 'step-*.svg' -print0
)

if [[ "$asset_count" -ne 6 ]]; then
  printf 'formula asset test expected 6 SVGs, got %s\n' "$asset_count" >&2
  exit 1
fi

printf 'FORMULA ASSET TEST: passed\n'
