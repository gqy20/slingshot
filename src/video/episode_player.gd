class_name SlingshotEpisodePlayer
extends Node

const EpisodeCanvas = preload("res://src/video/episode_canvas.gd")
const EpisodeHud = preload("res://src/video/episode_hud.gd")
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
var running := false
var last_phase := ""


func start(
	normalized_episode: Dictionary,
	run_bundle: Dictionary,
	output_sidecar_path: String,
	subtitle_path: String = ""
) -> void:
	episode = normalized_episode
	bundle = run_bundle
	sidecar_path = output_sidecar_path
	analysis = ResultAnalyzer.analyze(episode, bundle)

	canvas = EpisodeCanvas.new()
	canvas.name = "EpisodeCanvas"
	add_child(canvas)
	canvas.configure(episode, bundle, analysis)

	hud = EpisodeHud.new()
	hud.name = "EpisodeHud"
	add_child(hud)
	var subtitle_result := SubtitleTrack.load_path(subtitle_path)
	if not subtitle_result["ok"]:
		push_error(subtitle_result["error"])
		get_tree().quit(3)
		return
	hud.configure(episode, analysis, subtitle_result["cues"])

	frame_index = 0
	running = true
	print(
		"[episode:playback] episode=%s duration=%.3f variants=%d"
		% [episode["id"], episode["duration_sec"], bundle["records"].size()]
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
	if video_time + 1.0 / fps >= float(episode["duration_sec"]):
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
		"frame_count": frame_index,
		"video": episode["video"],
		"analysis": analysis,
		"narration": episode.get("narration", {}),
		"subtitle_cue_count": subtitle_cues_count(),
		"variants": summaries,
		"provenance": {
			"engine": Engine.get_version_info().get("string", "unknown"),
			"record_engine": bundle.get("engine", "unknown"),
			"record_schema_version": bundle.get("schema_version", 0),
			"deterministic_seeded": true,
		},
	}
	var result := RunRecord.write_json(sidecar_path, sidecar)
	if result != OK:
		push_error("failed to write episode sidecar: %s" % error_string(result))
		get_tree().quit(3)
		return
	print("[episode:playback] sidecar=%s" % sidecar_path)
	get_tree().quit(0)


func subtitle_cues_count() -> int:
	return hud.subtitle_cues.size() if is_instance_valid(hud) else 0
