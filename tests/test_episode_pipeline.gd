extends RefCounted

const EpisodeLoader = preload("res://src/core/episode_loader.gd")
const ReplayTrack = preload("res://src/playback/replay_track.gd")
const EpisodeDirector = preload("res://src/video/episode_director.gd")
const ResultAnalyzer = preload("res://src/core/result_analyzer.gd")


func _record(id: String, label: String, range_m: float, event_time: float) -> Dictionary:
	return {
		"variant_id": id,
		"label": label,
		"color_html": "35C2FF",
		"tick_rate": 10,
		"duration_sec": 1.0,
		"frames": [
			{
				"time_sec": 0.0,
				"bird_position_px": [0.0, 10.0],
				"bird_rotation": 0.0,
				"bird_velocity_px_s": [10.0, 0.0],
				"target_position_px": [20.0, 10.0],
				"target_rotation": 0.0,
				"target_velocity_px_s": [0.0, 0.0],
			},
			{
				"time_sec": 0.1,
				"bird_position_px": [10.0, 10.0],
				"bird_rotation": 0.2,
				"bird_velocity_px_s": [10.0, 0.0],
				"target_position_px": [20.0, 10.0],
				"target_rotation": 0.0,
				"target_velocity_px_s": [0.0, 0.0],
			},
		],
		"events": [{"type": "first_contact", "time_sec": event_time}],
		"metrics": {"range_m": range_m},
	}


func run(t) -> void:
	var loaded := EpisodeLoader.load_path("res://content/episodes/smoke.json")
	t.check(loaded["ok"], "pipeline fixture loads")
	if not loaded["ok"]:
		return
	var episode: Dictionary = loaded["episode"]
	var first := _record("angle-30", "30°", 4.0, 0.4)
	var second := _record("angle-60", "60°", 3.0, 0.6)
	var bundle := {"records": [first, second]}

	var sample := ReplayTrack.sample(first, 0.05)
	t.check(sample["bird_position_px"] == Vector2(5.0, 10.0), "replay interpolates positions")
	t.check_close(sample["bird_rotation"], 0.1, 0.0001, "replay interpolates rotation")
	t.check_close(
		ReplayTrack.event_time(first, "first_contact"),
		0.4,
		0.0001,
		"replay finds event time"
	)

	t.check(EpisodeDirector.phase_for_time(episode, 0.0) == "QUESTION", "question phase")
	t.check(EpisodeDirector.phase_for_time(episode, 0.2) == "SETUP", "setup phase")
	t.check(EpisodeDirector.phase_for_time(episode, 0.4) == "FLIGHT", "flight phase")
	t.check(EpisodeDirector.phase_for_time(episode, 0.8) == "COMPARE", "compare phase")
	var times := EpisodeDirector.simulation_times(episode, bundle, 0.5)
	t.check(times.has("angle-30") and times.has("angle-60"), "director maps every variant")

	var analysis := ResultAnalyzer.analyze(episode, bundle)
	t.check(analysis["winner_id"] == "angle-30", "analyzer selects max metric")
	t.check_close(analysis["winner_value"], 4.0, 0.0001, "analyzer reports winner value")
