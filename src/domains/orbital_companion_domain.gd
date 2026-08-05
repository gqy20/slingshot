class_name SlingshotOrbitalCompanionDomain
extends RefCounted

const Solver = preload("res://src/simulation/quasi_satellite_solver.gd")
const EphemerisSolver = preload("res://src/simulation/horizons_ephemeris_solver.gd")
const Canvas = preload("res://src/video/canvases/orbital_companion_canvas.gd")
const MODELS := ["orbital_companion"]


static func model_ids() -> Array[String]:
	return MODELS.duplicate()


static func supports_model(model: String) -> bool:
	return model in MODELS


static func is_offline_model(model: String) -> bool:
	return model == "orbital_companion"


static func normalize_simulation(simulation: Dictionary) -> Dictionary:
	var normalized := simulation.duplicate(true)
	return {"ok": true, "error": "", "value": normalized}


static func normalize_preset(raw: Dictionary, _variant_color: String) -> Dictionary:
	if not raw.get("physics") is Dictionary or not raw.get("scene") is Dictionary:
		return _preset_failure("physics and scene must be objects")
	var physics: Dictionary = raw["physics"].duplicate(true)
	var scene: Dictionary = raw["scene"].duplicate(true)
	for key in ["pixels_per_meter", "orbital_period_years"]:
		if not _positive(physics.get(key)):
			return _preset_failure("physics.%s must be positive and finite" % key)
		physics[key] = float(physics[key])
	for key in ["semi_major_axis_au", "period_ratio", "analytic_year_span"]:
		if not _positive(scene.get(key)):
			return _preset_failure("scene.%s must be positive and finite" % key)
		scene[key] = float(scene[key])
	if not _number(scene.get("eccentricity")):
		return _preset_failure("scene.eccentricity must be numeric")
	scene["eccentricity"] = float(scene["eccentricity"])
	if scene["eccentricity"] < 0.0 or scene["eccentricity"] >= 0.5:
		return _preset_failure("scene.eccentricity must be between 0 and 0.5")
	for key in ["phase_offset_rad", "periapsis_angle_rad", "ground_y_m"]:
		if not _number(scene.get(key)):
			return _preset_failure("scene.%s must be numeric" % key)
		scene[key] = float(scene[key])
	var data_mode := String(scene.get("data_mode", "analytic"))
	if data_mode not in ["analytic", "horizons"]:
		return _preset_failure("scene.data_mode must be analytic or horizons")
	scene["data_mode"] = data_mode
	var ephemeris_path := String(scene.get("ephemeris_path", ""))
	if data_mode == "horizons" and (
		not ephemeris_path.begins_with("res://data/ephemerides/")
		or not FileAccess.file_exists(ephemeris_path)
	):
		return _preset_failure("scene.ephemeris_path must reference an existing project ephemeris")
	scene["ephemeris_path"] = ephemeris_path
	for key in ["window_start_jd", "window_end_jd"]:
		if not _number(scene.get(key)):
			return _preset_failure("scene.%s must be numeric" % key)
		scene[key] = float(scene[key])
	if scene["window_end_jd"] <= scene["window_start_jd"]:
		return _preset_failure("scene ephemeris window must have positive duration")
	for key in ["launch_position_m", "target_position_m"]:
		var vector: Variant = _vector(scene.get(key))
		if vector == null:
			return _preset_failure("scene.%s must contain two finite numbers" % key)
		scene[key] = vector
	return {"ok": true, "error": "", "warnings": [], "preset": {
		"id": String(raw.get("id", "orbital-companion")),
		"duration_sec": float(raw.get("duration_sec", 12.0)),
		"video": raw.get("video", {}).duplicate(true),
		"physics": physics,
		"scene": scene,
	}}


static func simulate_episode(episode: Dictionary) -> Dictionary:
	var records: Array = []
	for variant_value in episode["variants"]:
		var variant: Dictionary = variant_value
		var preset: Dictionary = variant["preset"]
		var record: Dictionary
		if preset["scene"]["data_mode"] == "horizons":
			record = EphemerisSolver.simulate(
				preset["scene"]["ephemeris_path"],
				int(episode["simulation"]["tick_rate"]),
				float(episode["simulation"]["duration_sec"]),
				float(preset["scene"]["window_start_jd"]),
				float(preset["scene"]["window_end_jd"])
			)
		else:
			record = Solver.simulate(
				preset,
				int(episode["simulation"]["tick_rate"]),
				float(episode["simulation"]["duration_sec"])
			)
		if record.has("error"):
			push_error("orbital simulation failed: %s" % record["error"])
			continue
		record["variant_id"] = variant["id"]
		record["label"] = variant["label"]
		record["color_html"] = variant["color_html"]
		records.append(record)
	return {"records": records, "extras": {"model_boundary": "planar conceptual model"}}


static func validate_record(record: Dictionary) -> String:
	for key in ["variant_id", "label", "color_html", "model_kind"]:
		if not record.get(key) is String or String(record[key]).is_empty():
			return "record.%s must be a non-empty string" % key
	if not record.get("frames") is Array or record["frames"].size() < 2:
		return "record.frames must contain at least two frames"
	if not record.get("metrics") is Dictionary:
		return "record.metrics must be an object"
	for metric in ["loop_closure_au", "period_ratio", "min_relative_distance_au", "max_relative_distance_au"]:
		if not _number(record["metrics"].get(metric)):
			return "record.metrics.%s must be numeric" % metric
	return ""


static func sample(record: Dictionary, time_sec: float) -> Dictionary:
	var frames: Array = record.get("frames", [])
	if frames.is_empty():
		return {}
	var tick_rate := maxi(1, int(record.get("tick_rate", 120)))
	var position := clampf(time_sec, 0.0, float(record.get("duration_sec", 0.0))) * tick_rate
	var lower_index := clampi(int(floor(position)), 0, frames.size() - 1)
	var upper_index := mini(lower_index + 1, frames.size() - 1)
	var weight := clampf(position - floor(position), 0.0, 1.0)
	var lower: Dictionary = frames[lower_index]
	var upper: Dictionary = frames[upper_index]
	var result := {}
	for key in ["earth_position_au", "earth_velocity_au_y", "asteroid_position_au", "asteroid_velocity_au_y", "relative_inertial_au", "relative_rotating_au"]:
		result[key] = _as_vector(lower[key]).lerp(_as_vector(upper[key]), weight)
	for key in ["solar_distance_au", "orbital_speed_au_y", "earth_angle_rad"]:
		result[key] = lerpf(float(lower[key]), float(upper[key]), weight)
	return result


static func canvas_script() -> Script:
	return Canvas


static func audit_bundle(_bundle: Dictionary) -> PackedStringArray:
	return PackedStringArray()


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _positive(value: Variant) -> bool:
	return _number(value) and float(value) > 0.0


static func _vector(value: Variant) -> Variant:
	if not value is Array or value.size() != 2 or not _number(value[0]) or not _number(value[1]):
		return null
	return Vector2(float(value[0]), float(value[1]))


static func _as_vector(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	return Vector2(float(value[0]), float(value[1]))


static func _preset_failure(message: String) -> Dictionary:
	return {"ok": false, "error": message, "warnings": [], "preset": {}}
