extends RefCounted

const EpisodeLoader = preload("res://src/core/episode_loader.gd")
const EpisodeTemplates = preload("res://src/core/episode_templates.gd")
const ExplanationRegistry = preload("res://src/video/explanations/explanation_registry.gd")


func run(t) -> void:
	var story := {
		"question_sec": 15.0,
		"explain_sec": 30.0,
		"setup_sec": 15.0,
		"flight_sec": 20.0,
		"compare_sec": 40.0,
	}
	var explanation := {
		"module": "angle_components",
		"steps": [{}, {}, {}],
	}
	var expanded := EpisodeTemplates.expand(
		EpisodeTemplates.EDITORIAL_COMPARISON,
		story,
		explanation,
		{
			"hook": {"headline": "A ≠ B", "focus": "a"},
			"flight": {"focus": "winner"},
		}
	)
	t.check(expanded["ok"], "editorial comparison template expands")
	if expanded["ok"]:
		var beats: Array = expanded["beats"]
		t.check(beats.size() == 14, "three-step explanation produces fourteen standard beats")
		t.check(beats[0]["headline"] == "A ≠ B", "beat override replaces presentational copy")
		t.check(beats[9]["focus"] == "winner", "beat override selects the tracked subject")
		t.check_close(float(beats[-1]["at"]) + float(beats[-1]["duration"]), 120.0, 0.0001, "template covers the complete episode")
		var cursor := 0.0
		for beat_value in beats:
			var beat: Dictionary = beat_value
			t.check_close(float(beat["at"]), cursor, 0.0001, "template beat starts at the previous boundary")
			t.check(not String(beat["camera_reason"]).is_empty(), "template supplies a framing reason")
			t.check(not String(beat["intent"]).is_empty(), "template supplies one narrative intent")
			cursor += float(beat["duration"])
		t.check(beats[4]["camera_action"] == "hold", "later formula steps keep the same geometry")
		t.check(beats[7]["camera_action"] == "hold", "prediction copy does not move the setup view")

	var unknown_override := EpisodeTemplates.expand(
		EpisodeTemplates.EDITORIAL_COMPARISON,
		story,
		explanation,
		{"missing": {"headline": "invalid"}}
	)
	t.check(not unknown_override["ok"], "template rejects overrides for unknown beat ids")

	t.check(ExplanationRegistry.has_module("angle_components"), "angle explanation is registered")
	t.check(ExplanationRegistry.has_module("spring_energy"), "spring explanation is registered")
	t.check(not ExplanationRegistry.has_module("missing"), "unknown explanation is not registered")
	var angle_module := ExplanationRegistry.create("angle_components")
	var energy_module := ExplanationRegistry.create("spring_energy")
	t.check(angle_module != null and not angle_module.hides_physical_stage(), "angle explanation keeps the physical stage")
	t.check(energy_module != null and energy_module.hides_physical_stage(), "energy explanation owns its clean diagram stage")

	var raw: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/episodes/s01e01-angle-sweep.json")
	)
	raw.erase("beats")
	raw["beat_template"] = EpisodeTemplates.EDITORIAL_COMPARISON
	raw["beat_overrides"] = {"hook": {"headline": "模板化开场"}}
	var compact := EpisodeLoader.validate_dict(raw)
	t.check(compact["ok"], "loader accepts a compact template-driven episode")
	if compact["ok"]:
		t.check(compact["episode"]["beats"].size() == 14, "loader materializes standard beats")
		t.check(compact["episode"]["beats"][0]["headline"] == "模板化开场", "loader applies compact beat overrides")

	var conflicting: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/episodes/s01e01-angle-sweep.json")
	)
	conflicting["beat_template"] = EpisodeTemplates.EDITORIAL_COMPARISON
	t.check(not EpisodeLoader.validate_dict(conflicting)["ok"], "loader rejects simultaneous beats and beat_template")

	var unknown_module: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/episodes/s01e01-angle-sweep.json")
	)
	unknown_module["story"]["explanation"]["module"] = "missing"
	t.check(not EpisodeLoader.validate_dict(unknown_module)["ok"], "loader rejects an unregistered explanation module")
