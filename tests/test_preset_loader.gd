extends RefCounted

const PresetLoader = preload("res://src/core/preset_loader.gd")


func _valid() -> Dictionary:
	return {
		"id": "basic-shot",
		"seed": 20260722,
		"duration_sec": 12.0,
		"video": {"width": 1920, "height": 1080, "fps": 60},
		"physics": {
			"pixels_per_meter": 100.0,
			"gravity_mps2": 9.81,
			"bird_mass_kg": 1.0,
			"target_mass_kg": 3.0,
			"spring_k_npm": 160.0,
			"stretch_m": 0.9,
			"efficiency": 0.82,
			"launch_angle_deg": 45.0,
		},
		"scene": {
			"ground_y_m": 9.2,
			"launch_position_m": [2.4, 7.6],
			"target_position_m": [13.2, 7.6],
			"bird_color": "#E94F37",
			"accent_color": "#35C2FF",
			"target_color": "#73C66A",
		},
	}


func run(t) -> void:
	var accepted := PresetLoader.validate_dict(_valid())
	t.check(accepted["ok"], "valid preset accepted")
	t.check(
		accepted["preset"]["scene"]["launch_position_m"] == Vector2(2.4, 7.6),
		"launch position normalized"
	)
	t.check(
		accepted["preset"]["scene"]["bird_color"] == Color("#E94F37"),
		"bird color normalized"
	)

	var missing_id := _valid()
	missing_id.erase("id")
	t.check(not PresetLoader.validate_dict(missing_id)["ok"], "missing id rejected")

	var wrong_width := _valid()
	wrong_width["video"]["width"] = 1280
	t.check(not PresetLoader.validate_dict(wrong_width)["ok"], "non-1080p width rejected")

	var wrong_fps := _valid()
	wrong_fps["video"]["fps"] = 30
	t.check(not PresetLoader.validate_dict(wrong_fps)["ok"], "non-60 fps rejected")

	var bad_mass := _valid()
	bad_mass["physics"]["bird_mass_kg"] = 0.0
	t.check(not PresetLoader.validate_dict(bad_mass)["ok"], "nonpositive mass rejected")

	var bad_efficiency := _valid()
	bad_efficiency["physics"]["efficiency"] = 1.2
	t.check(not PresetLoader.validate_dict(bad_efficiency)["ok"], "efficiency over one rejected")

	var bad_coordinate := _valid()
	bad_coordinate["scene"]["target_position_m"] = [13.2]
	t.check(not PresetLoader.validate_dict(bad_coordinate)["ok"], "malformed coordinate rejected")

	var bad_color := _valid()
	bad_color["scene"]["accent_color"] = "electric blue"
	t.check(not PresetLoader.validate_dict(bad_color)["ok"], "invalid color rejected")

	var unknown := _valid()
	unknown["mystery"] = 7
	var warned := PresetLoader.validate_dict(unknown)
	t.check(warned["ok"] and warned["warnings"].size() == 1, "unknown top-level key warns")

	var loaded := PresetLoader.load_path("res://presets/default.json")
	t.check(loaded["ok"], "default preset loads")
	if loaded["ok"]:
		t.check_close(loaded["preset"]["duration_sec"], 12.0, 0.0001, "default duration")
