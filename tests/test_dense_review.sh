#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/.." && pwd)"
review_tmp="$(mktemp -d /tmp/slingshot-dense-test.XXXXXX)"
cleanup() {
  find "$review_tmp" -depth -delete
}
trap cleanup EXIT

ffmpeg -y -loglevel error -f lavfi -i 'color=c=#0E1116:s=320x180:r=30:d=2' \
  -c:v libx264 -pix_fmt yuv420p "$review_tmp/synthetic.mp4"

DENSE_REVIEW_FRAMES_DIR="$review_tmp/frames" \
DENSE_REVIEW_SHEETS_DIR="$review_tmp/sheets" \
  "$PROJECT_ROOT/scripts/review_dense.sh" "$review_tmp/synthetic.mp4" >/dev/null

frame_dir="$review_tmp/frames/synthetic/dense-2fps"
sheet_dir="$review_tmp/sheets/synthetic/dense-2fps"
test "$(find "$frame_dir" -maxdepth 1 -name '*--sample.png' -printf '.' | wc -c)" -eq 4
test "$(find "$sheet_dir" -maxdepth 1 -name '*.png' -printf '.' | wc -c)" -eq 1
test "$(wc -l <"$frame_dir/index.tsv")" -eq 5
grep -Fq 'sample_fps=2' "$frame_dir/dense-2fps.manifest.txt"
grep -Fq 'sample_interval_ms=500' "$frame_dir/dense-2fps.manifest.txt"

printf 'DENSE REVIEW TEST: passed\n'
