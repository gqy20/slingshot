#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

git -C "$PROJECT_ROOT" config core.hooksPath .githooks
printf 'git-hooks: installed core.hooksPath=.githooks\n'
