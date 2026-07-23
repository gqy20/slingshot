class_name SlingshotEpisodePlayer
extends Node

const EpisodeCanvas = preload("res://src/video/episode_canvas.gd")
const EpisodeHud = preload("res://src/video/episode_hud.gd")
const EpisodeLayout = preload("res://src/video/episode_layout.gd")
const EpisodeDirector = preload("res://src/video/episode_director.gd")
const ReplayTrack = preload("res://src/playback/replay_track.gd")
const ResultAnalyzer = preload("res://src/core/result_analyzer.gd")
const RunRecord = preload("res://src/core/run_record.gd")
const SubtitleTrack = preload("res://src/playback/subtitle_track.gd")

var episode: Dictionary = {}
var bundle: Dictionary = {}
var analysis: Dictionary = {}
var sidecar_path := ""
var canvas: SlingshotEpisodeCanvas
var hud: SlingshotEpisodeHud
var frame_index := 0
var frame_end_exclusive := 0
var total_frame_count := 0
var running := false
var last_phase := ""


func start(
	normalized_episode: Dictionary,
	run_bundle: Dictionary,
	output_sidecar_path: String,
	subtitle_path: String = "",
	frame_start: int = 0,
	frame_end: int = -1
) -> void:
	episode = normalized_episode
	bundle = run_bundle
	sidecar_path = output_sidecar_path
	analysis = ResultAnalyzer.analyze(episode, bundle)
	var layout_errors := EpisodeLayout.validate_static_regions()
	layout_errors.append_array(EpisodeLayout.audit_bundle(bundle))
	if not layout_errors.is_empty():
		push_error("episode layout audit failed: %s" % "; ".join(layout_errors))
		get_tree().quit(3)
		return

	canvas = EpisodeCanvas.new()
	canvas.name = "EpisodeCanvas"
	add_child(canvas)
	canvas.configure(episode, bundle, analysis)
	var render_scale := float(episode["video"]["width"]) / 1920.0
	canvas.scale = Vector2(render_scale, render_scale)

	hud = EpisodeHud.new()
	hud.name = "EpisodeHud"
	add_child(hud)
	hud.scale = Vector2(render_scale, render_scale)
	var subtitle_result := SubtitleTrack.load_path(subtitle_path)
	if not subtitle_result["ok"]:
		push_error(subtitle_result["error"])
		get_tree().quit(3)
		return
	var subtitle_layout := SubtitleTrack.validate_layout(subtitle_result["cues"])
	if not subtitle_layout["ok"]:
		push_error(subtitle_layout["error"])
		get_tree().quit(3)
		return
	hud.configure(episode, analysis, subtitle_result["cues"])

	var fps := float(episode["video"]["fps"])
	total_frame_count = roundi(float(episode["duration_sec"]) * fps)
	var frame_range := resolve_frame_range(total_frame_count, frame_start, frame_end)
	frame_index = frame_range.x
	frame_end_exclusive = frame_range.y
	if frame_index >= frame_end_exclusive:
		push_error(
			"invalid playback frame range [%d, %d) for %d frames"
			% [frame_index, frame_end_exclusive, total_frame_count]
		)
		get_tree().quit(3)
		return
	last_phase = ""
	running = true
	print(
		"[episode:playback] episode=%s duration=%.3f variants=%d frames=[%d,%d)/%d"
		% [
			episode["id"],
			episode["duration_sec"],
			bundle["records"].size(),
			frame_index,
			frame_end_exclusive,
			total_frame_count,
		]
	)


func _process(_delta: float) -> void:
	if not running:
		return
	var fps := float(episode["video"]["fps"])
	var video_time := float(frame_index) / fps
	var phase := EpisodeDirector.phase_for_time(episode, video_time)
	var times := EpisodeDirector.simulation_times(episode, bundle, video_time)
	var states := {}
	for record_value in bundle["records"]:
		var record: Dictionary = record_value
		var id: String = record["variant_id"]
		states[id] = ReplayTrack.sample(record, float(times.get(id, 0.0)))
	canvas.set_playback(phase, times, states, video_time)
	if phase != last_phase:
		last_phase = phase
		hud.set_phase(phase)
	hud.set_elapsed(video_time, times)

	frame_index += 1
	if frame_index >= frame_end_exclusive:
		_finish()


func _finish() -> void:
	running = false
	var summaries: Array = []
	for record_value in bundle["records"]:
		var record: Dictionary = record_value
		summaries.append({
			"variant_id": record["variant_id"],
			"label": record["label"],
			"color_html": record["color_html"],
			"events": record["events"],
			"metrics": record["metrics"],
		})
	var sidecar := {
		"schema_version": 1,
		"episode_id": episode["id"],
		"series": episode["series"],
		"season": episode["season"],
		"episode": episode["episode"],
		"title": episode["title"],
		"question": episode["question"],
		"duration_sec": episode["duration_sec"],
		"frame_count": total_frame_count,
		"video": episode["video"],
		"analysis": analysis,
		"narration": episode.get("narration", {}),
		"subtitle_cue_count": subtitle_cues_count(),
		"layout": {
			"plot_safe_by_phase": true,
			"subject_overlap_audited": true,
			"subtitle_max_characters": 88,
			"subtitle_max_explicit_lines": 2,
		},
		"variants": summaries,
		"provenance": {
			"engine": Engine.get_version_info().get("string", "unknown"),
			"record_engine": bundle.get("engine", "unknown"),
			"record_schema_version": bundle.get("schema_version", 0),
			"deterministic_seeded": true,
		},
	}
	if not sidecar_path.is_empty():
		var result := RunRecord.write_json(sidecar_path, sidecar)
		if result != OK:
			push_error("failed to write episode sidecar: %s" % error_string(result))
			get_tree().quit(3)
			return
		print("[episode:playback] sidecar=%s" % sidecar_path)
	get_tree().quit(0)


func subtitle_cues_count() -> int:
	return hud.subtitle_cues.size() if is_instance_valid(hud) else 0


static func resolve_frame_range(total_frames: int, start_frame: int, end_frame: int) -> Vector2i:
	var bounded_total := maxi(0, total_frames)
	var bounded_start := clampi(start_frame, 0, bounded_total)
	var bounded_end := (
		bounded_total
		if end_frame < 0
		else clampi(end_frame, 0, bounded_total)
	)
	return Vector2i(bounded_start, bounded_end)
