#!/usr/bin/env bash

if [[ -z "${PROJECT_ROOT:-}" ]]; then
  printf 'render-paths: PROJECT_ROOT must be set before sourcing\n' >&2
  return 2
fi

RENDER_ROOT="$PROJECT_ROOT/renders"
RENDER_WORK_DIR="$RENDER_ROOT/work"
RENDER_MASTERS_DIR="$RENDER_ROOT/masters"
RENDER_DELIVERIES_DIR="$RENDER_ROOT/deliveries"
RENDER_ARCHIVE_DIR="$RENDER_ROOT/archive"
RENDER_CACHE_DIR="$RENDER_ROOT/cache"

episode_work_dir() { printf '%s/%s' "$RENDER_WORK_DIR" "$1"; }
episode_preview_dir() { printf '%s/%s/previews' "$RENDER_WORK_DIR" "$1"; }
episode_review_dir() { printf '%s/%s/review' "$RENDER_WORK_DIR" "$1"; }
episode_master_dir() { printf '%s/%s' "$RENDER_MASTERS_DIR" "$1"; }
episode_audio_dir() { printf '%s/%s/audio' "$RENDER_MASTERS_DIR" "$1"; }
episode_delivery_dir() { printf '%s/%s' "$RENDER_DELIVERIES_DIR" "$1"; }
episode_archive_dir() { printf '%s/%s' "$RENDER_ARCHIVE_DIR" "$1"; }
episode_id_from_video() {
	local video_dir
	video_dir="$(dirname "$1")"
	if [[ "$(dirname "$video_dir")" == "$RENDER_MASTERS_DIR" ]]; then
		basename "$video_dir"
	else
		basename "${1%.mp4}"
	fi
}

# Compatibility aliases for scripts not yet converted to episode-scoped helpers.
RENDER_FINAL_DIR="$RENDER_MASTERS_DIR"
RENDER_FRAMES_DIR="$RENDER_WORK_DIR"
RENDER_CONTACT_SHEETS_DIR="$RENDER_WORK_DIR"
RENDER_PREVIEWS_DIR="$RENDER_WORK_DIR"
RENDER_SMOKE_DIR="$RENDER_CACHE_DIR/smoke"
RENDER_NARRATION_DIR="$RENDER_MASTERS_DIR"
RENDER_AUDIO_DIR="$RENDER_MASTERS_DIR"

export RENDER_ROOT RENDER_FINAL_DIR RENDER_FRAMES_DIR
export RENDER_CONTACT_SHEETS_DIR RENDER_PREVIEWS_DIR
export RENDER_SMOKE_DIR RENDER_NARRATION_DIR
export RENDER_AUDIO_DIR
export RENDER_WORK_DIR RENDER_MASTERS_DIR RENDER_DELIVERIES_DIR
export RENDER_ARCHIVE_DIR RENDER_CACHE_DIR
