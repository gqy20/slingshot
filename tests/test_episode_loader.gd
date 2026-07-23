extends RefCounted

const EpisodeLoader = preload("res://src/core/episode_loader.gd")


func run(t) -> void:
	var loaded := EpisodeLoader.load_path("res://content/episodes/smoke.json")
	t.check(loaded["ok"], "smoke episode loads")
	if not loaded["ok"]:
		return
	var episode: Dictionary = loaded["episode"]
	t.check(episode["variants"].size() == 2, "episode expands variants")
	t.check_close(episode["duration_sec"], 1.1, 0.0001, "episode duration derives from story")
	t.check(
		episode["variants"][0]["preset"]["physics"]["launch_angle_deg"] == 30.0,
		"variant override applied"
	)
	t.check(
		episode["variants"][1]["preset"]["scene"]["bird_color"] == Color("#E48865"),
		"variant color applied to preset"
	)
	var colors: Dictionary = episode["theme"]["colors"]
	t.check(colors["background"] == Color("#0E1116"), "editorial background token loads")
	t.check(colors["surface_elevated"] == Color("#1D2430"), "elevated surface token loads")
	t.check(colors["accent"] == Color("#F0B35A"), "brand accent token loads")

	var raw: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/episodes/smoke.json")
	)
	var wrong_schema: Dictionary = raw.duplicate(true)
	wrong_schema["schema_version"] = 2
	t.check(not EpisodeLoader.validate_dict(wrong_schema)["ok"], "unknown schema rejected")

	var one_variant: Dictionary = raw.duplicate(true)
	one_variant["variants"] = [one_variant["variants"][0]]
	t.check(not EpisodeLoader.validate_dict(one_variant)["ok"], "single variant rejected")

	var bad_override: Dictionary = raw.duplicate(true)
	bad_override["variants"][0]["overrides"] = {"video.fps": 30}
	t.check(not EpisodeLoader.validate_dict(bad_override)["ok"], "unsafe override rejected")

	var bad_fps: Dictionary = raw.duplicate(true)
	bad_fps["video"]["fps"] = 24
	t.check(not EpisodeLoader.validate_dict(bad_fps)["ok"], "unsupported episode fps rejected")

	var bad_resolution: Dictionary = raw.duplicate(true)
	bad_resolution["video"]["width"] = 2560
	t.check(
		not EpisodeLoader.validate_dict(bad_resolution)["ok"],
		"unsupported episode resolution rejected"
	)

	var duplicate: Dictionary = raw.duplicate(true)
	duplicate["variants"][1]["id"] = duplicate["variants"][0]["id"]
	t.check(not EpisodeLoader.validate_dict(duplicate)["ok"], "duplicate variant ids rejected")

	for production_path in [
		"res://content/episodes/s01e01-angle-sweep.json",
		"res://content/episodes/s01e02-stretch-sweep.json",
	]:
		var production := EpisodeLoader.load_path(production_path)
		t.check(production["ok"], "production episode loads: %s" % production_path)
		if production["ok"]:
			var story: Dictionary = production["episode"]["story"]
			t.check(
				not story["show_target"],
				"range episode hides target"
			)
			t.check(
				production["episode"]["duration_sec"] >= 60.0,
				"production episode provides at least one minute"
			)
			t.check(
				production["episode"]["video"]["fps"] == 30,
				"long-form episode uses device-friendly 30 fps"
			)
			t.check(
				production["episode"]["video"]["width"] == 3840,
				"production episode renders at native 4K width"
			)
			t.check(
				not production["episode"]["narration"].is_empty(),
				"production episode declares reproducible narration"
			)
			t.check(
				not str(story["control_label"]).is_empty(),
				"production episode states its controlled variables"
			)

	var episode_one: Dictionary = EpisodeLoader.load_path(
		"res://content/episodes/s01e01-angle-sweep.json"
	)["episode"]
	var episode_two: Dictionary = EpisodeLoader.load_path(
		"res://content/episodes/s01e02-stretch-sweep.json"
	)["episode"]
	t.check(
		episode_one["story"]["secondary_metric"] == "max_height_m",
		"angle episode compares height as well as range"
	)
	t.check(
		episode_two["story"]["secondary_metric"] == "spring_energy_j",
		"stretch episode exposes the energy evidence"
	)
