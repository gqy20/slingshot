#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REQUIRED_TYPST_VERSION="0.15.1"
TEMPLATE_VERSION="2"
CHECK_ONLY=0
EPISODES=()

usage() {
  printf 'usage: %s [--check] [episode.json ...]\n' "$0" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)
      CHECK_ONLY=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --*)
      printf 'formula-assets: unknown option: %s\n' "$1" >&2
      usage
      exit 2
      ;;
    *)
      EPISODES+=("$1")
      shift
      ;;
  esac
done

for required_command in jq realpath sha256sum awk; do
  command -v "$required_command" >/dev/null 2>&1 || {
    printf 'formula-assets: missing command: %s\n' "$required_command" >&2
    exit 2
  }
done

if [[ "$CHECK_ONLY" -eq 0 ]]; then
  command -v typst >/dev/null 2>&1 || {
    printf 'formula-assets: typst %s is required to rebuild formula SVGs\n' \
      "$REQUIRED_TYPST_VERSION" >&2
    exit 2
  }
  installed_typst_version="$(typst --version | awk '{print $2}')"
  if [[ "$installed_typst_version" != "$REQUIRED_TYPST_VERSION" ]]; then
    printf 'formula-assets: expected typst %s, got %s\n' \
      "$REQUIRED_TYPST_VERSION" "$installed_typst_version" >&2
    exit 2
  fi
fi

if [[ "${#EPISODES[@]}" -eq 0 ]]; then
  while IFS= read -r -d '' episode_path; do
    EPISODES+=("$episode_path")
  done < <(
    find "$PROJECT_ROOT/content/episodes" -maxdepth 1 -type f \
      -name 's[0-9][0-9]e[0-9][0-9]-*.json' -print0 | sort -z
  )
fi

formula_tmp="$(mktemp -d /tmp/slingshot-formulas.XXXXXX)"
cleanup() {
  find "$formula_tmp" -depth -delete
}
trap cleanup EXIT

asset_count=0
cached_count=0
for episode_input in "${EPISODES[@]}"; do
  episode_abs="$(realpath "$episode_input")"
  episode_id="$(jq -er '.id' "$episode_abs")"
  asset_dir="$(jq -r '.story.explanation.asset_dir // ""' "$episode_abs")"
  typst_step_count="$(jq '[.story.explanation.steps[]? | select((.typst // "") != "")] | length' "$episode_abs")"
  if [[ "$typst_step_count" -eq 0 ]]; then
    continue
  fi
  if [[ "$asset_dir" != res://assets/generated/formulas/* || "$asset_dir" == *'..'* ]]; then
    printf 'formula-assets: unsafe asset_dir in %s: %s\n' "$episode_id" "$asset_dir" >&2
    exit 2
  fi
  step_count="$(jq '.story.explanation.steps | length' "$episode_abs")"
  if [[ "$typst_step_count" -ne "$step_count" ]]; then
    printf 'formula-assets: every explanation step must declare typst: %s\n' "$episode_id" >&2
    exit 2
  fi
  theme_path="$(jq -er '.theme' "$episode_abs")"
  if [[ "$theme_path" != res://* ]]; then
    printf 'formula-assets: theme must use res:// path: %s\n' "$episode_id" >&2
    exit 2
  fi
  theme_abs="$PROJECT_ROOT/${theme_path#res://}"
  formula_color="$(jq -er '.colors.text' "$theme_abs")"
  output_dir="$PROJECT_ROOT/${asset_dir#res://}"
  mkdir -p "$output_dir"

  episode_manifest="$formula_tmp/${episode_id}.manifest.txt"
  {
    printf 'episode=%s\n' "$episode_id"
    printf 'typst_version=%s\n' "$REQUIRED_TYPST_VERSION"
    printf 'template_version=%s\n' "$TEMPLATE_VERSION"
    printf 'math_font=New Computer Modern Math\n'
    printf 'format=svg\nbackground=transparent\n'
  } >"$episode_manifest"

  for ((step_index = 0; step_index < step_count; step_index += 1)); do
    step_number=$((step_index + 1))
    printf -v step_name 'step-%02d' "$step_number"
    typst_source="$(jq -er ".story.explanation.steps[$step_index].typst" "$episode_abs")"
    fallback_text="$(jq -er ".story.explanation.steps[$step_index].equation" "$episode_abs")"
    source_hash="$({
      printf 'typst_version=%s\n' "$REQUIRED_TYPST_VERSION"
      printf 'template_version=%s\n' "$TEMPLATE_VERSION"
      printf 'fill=%s\n' "$formula_color"
      printf 'source=%s\n' "$typst_source"
    } | sha256sum | awk '{print $1}')"
    output_svg="$output_dir/$step_name.svg"
    output_hash="$output_dir/$step_name.sha256"
    cached_hash=""
    if [[ -f "$output_hash" ]]; then
      cached_hash="$(tr -d '[:space:]' <"$output_hash")"
    fi
    if [[ "$cached_hash" == "$source_hash" && -s "$output_svg" ]]; then
      cached_count=$((cached_count + 1))
    elif [[ "$CHECK_ONLY" -eq 1 ]]; then
      printf 'formula-assets: stale or missing: %s/%s.svg\n' "$episode_id" "$step_name" >&2
      exit 1
    else
      source_file="$formula_tmp/$episode_id-$step_name.typ"
      compiled_svg="$formula_tmp/$episode_id-$step_name.svg"
      {
        # The UI consumes a 900x96 logical rectangle. Rasterizing the SVG at
        # twice that size keeps the imported texture sharp in native 4K.
        printf '#set page(width: 1800pt, height: 192pt, margin: 0pt, fill: none)\n'
        printf '#set text(fill: rgb("%s"), size: 96pt)\n' "$formula_color"
        printf '#show math.equation: set text(font: "New Computer Modern Math")\n'
        printf '#align(center + horizon)[$ %s $]\n' "$typst_source"
      } >"$source_file"
      typst compile --ignore-system-fonts --creation-timestamp 0 \
        "$source_file" "$compiled_svg"
      if [[ ! -s "$compiled_svg" ]] || ! grep -q '<svg' "$compiled_svg"; then
        printf 'formula-assets: Typst produced an invalid SVG: %s/%s\n' \
          "$episode_id" "$step_name" >&2
        exit 1
      fi
      if grep -q '<text' "$compiled_svg"; then
        printf 'formula-assets: SVG must contain paths instead of system text: %s/%s\n' \
          "$episode_id" "$step_name" >&2
        exit 1
      fi
      mv "$compiled_svg" "$output_svg"
      printf '%s\n' "$source_hash" >"$output_hash"
    fi
    printf '%s.svg typst_sha256=%s fallback=%s\n' \
      "$step_name" "$source_hash" "$fallback_text" >>"$episode_manifest"
    asset_count=$((asset_count + 1))
  done

  if [[ "$CHECK_ONLY" -eq 1 ]]; then
    if [[ ! -s "$output_dir/formulas.manifest.txt" ]]; then
      printf 'formula-assets: manifest missing: %s\n' "$episode_id" >&2
      exit 1
    fi
  else
    mv "$episode_manifest" "$output_dir/formulas.manifest.txt"
  fi
done

if [[ "$CHECK_ONLY" -eq 1 ]]; then
  printf 'formula-assets: verified assets=%s\n' "$asset_count"
else
  printf 'formula-assets: built assets=%s cached=%s typst=%s\n' \
    "$asset_count" "$cached_count" "$REQUIRED_TYPST_VERSION"
fi
