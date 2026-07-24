#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'usage: %s <episode.json>\n' "$0" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"
episode_path="$1"
if [[ ! -f "$episode_path" ]]; then
  printf 'episode-validation: episode not found: %s\n' "$episode_path" >&2
  exit 2
fi

"$GODOT_BIN" --headless --path "$PROJECT_ROOT" \
  --script res://scripts/validate_episode.gd -- "$episode_path"
