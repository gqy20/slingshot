class_name SlingshotTrackRaceDomain
extends RefCounted

const Solver = preload("res://src/simulation/brachistochrone_solver.gd")
const Canvas = preload("res://src/video/canvases/track_race_canvas.gd")

const MODELS := ["track_race"]
const TRACK_KINDS := ["line", "circular_arc", "cycloid"]


static func model_ids() -> Array[String]:
	return MODELS.duplicate()


static func supports_model(model: String) -> bool:
	return model in MODELS


static func is_offline_model(model: String) -> bool:
	return model == "track_race"


static func normalize_simulation(simulation: Dictionary) -> Dictionary:
	var steps_value: Variant = simulation.get("integration_steps", 8000)
	if not steps_value is int and not steps_value is float:
		return _failure("simulation.integration_steps must be numeric")
	var steps := int(steps_value)
	if steps < 1000 or steps > 50000:
		return _failure("simulation.integration_steps must be between 1000 and 50000")
	var normalized := simulation.duplicate(true)
	normalized["integration_steps"] = steps
	return {"ok": true, "error": "", "value": normalized}


static func normalize_preset(raw: Dictionary, _variant_color: String) -> Dictionary:
	if not raw.get("id") is String or String(raw["id"]).is_empty():
		return _preset_failure("id must be a non-empty string")
	if not raw.get("physics") is Dictionary:
		return _preset_failure("physics must be an object")
	if not raw.get("scene") is Dictionary:
		return _preset_failure("scene must be an object")
	var physics: Dictionary = raw["physics"].duplicate(true)
	for key in ["pixels_per_meter", "gravity_mps2", "mass_kg"]:
		if not _positive_finite(physics.get(key)):
			return _preset_failure("physics.%s must be positive and finite" % key)
		physics[key] = float(physics[key])
	var scene: Dictionary = raw["scene"].duplicate(true)
	for key in ["horizontal_span_m", "vertical_drop_m"]:
		if not _positive_finite(scene.get(key)):
			return _preset_failure("scene.%s must be positive and finite" % key)
		scene[key] = float(scene[key])
	var origin: Variant = _vector(scene.get("origin_px"))
	if origin == null:
		return _preset_failure("scene.origin_px must contain two finite numbers")
	scene["origin_px"] = origin
	var track_kind := String(scene.get("track_kind", ""))
	if track_kind not in TRACK_KINDS:
		return _preset_failure("scene.track_kind must be one of %s" % [TRACK_KINDS])
	scene["track_kind"] = track_kind
	return {
		"ok": true,
		"error": "",
		"warnings": [],
		"preset": {
			"id": String(raw["id"]),
			"duration_sec": float(raw.get("duration_sec", 4.0)),
			"video": raw.get("video", {}).duplicate(true),
			"physics": physics,
			"scene": scene,
		},
	}


static func simulate_episode(episode: Dictionary) -> Dictionary:
	var tick_rate := int(episode["simulation"]["tick_rate"])
	var duration := float(episode["simulation"]["duration_sec"])
	var steps := int(episode["simulation"]["integration_steps"])
	var records: Array = []
	for variant_value in episode["variants"]:
		var variant: Dictionary = variant_value
		var record := Solver.simulate(variant["preset"], tick_rate, duration, steps)
		record["variant_id"] = variant["id"]
		record["label"] = variant["label"]
		record["color_html"] = variant["color_html"]
		records.append(record)
		print(
			"[episode:simulate] complete=%s arrival=%.4f path=%.3f"
			% [variant["id"], record["metrics"]["arrival_time_sec"], record["metrics"]["path_length_m"]]
		)
	return {"records": records, "extras": {}}


static func validate_record(record: Dictionary) -> String:
	for key in ["variant_id", "label", "color_html"]:
		if not record.get(key) is String or String(record[key]).is_empty():
			return "record.%s must be a non-empty string" % key
	if not record.get("frames") is Array or record["frames"].is_empty():
		return "record.frames must be a non-empty array"
	if not record.get("path_points_px") is Array or record["path_points_px"].size() < 2:
		return "record.path_points_px must contain a sampled path"
	if not record.get("metrics") is Dictionary:
		return "record.metrics must be an object"
	for metric in [
		"arrival_time_sec", "arrival_speed_mps", "path_length_m", "max_energy_error_j"
	]:
		if not _is_number(record["metrics"].get(metric)):
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
	var arrival_time := float(record.get("metrics", {}).get("arrival_time_sec", INF))
	var arrived := time_sec >= arrival_time
	var path_speed := lerpf(
		float(lower.get("path_speed_mps", lower["speed_mps"])),
		float(upper.get("path_speed_mps", upper["speed_mps"])),
		weight
	)
	return {
		"position_px": _as_vector(lower["position_px"]).lerp(_as_vector(upper["position_px"]), weight),
		"speed_mps": 0.0 if arrived else path_speed,
		"kinetic_energy_j": lerpf(float(lower["kinetic_energy_j"]), float(upper["kinetic_energy_j"]), weight),
		"potential_energy_j": lerpf(float(lower["potential_energy_j"]), float(upper["potential_energy_j"]), weight),
		"progress": lerpf(float(lower["progress"]), float(upper["progress"]), weight),
		"arrived": arrived,
	}


static func canvas_script() -> Script:
	return Canvas


static func audit_bundle(bundle: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var safe_rect := Rect2(120, 170, 1680, 740)
	for record_value in bundle.get("records", []):
		var record: Dictionary = record_value
		for frame_value in record.get("frames", []):
			var frame: Dictionary = frame_value
			if not safe_rect.has_point(_as_vector(frame.get("position_px", Vector2.ZERO))):
				errors.append("%s track leaves canvas safe area" % record.get("variant_id", "unknown"))
				break
	return errors


static func _vector(value: Variant) -> Variant:
	if not value is Array or value.size() != 2:
		return null
	if not _is_number(value[0]) or not _is_number(value[1]):
		return null
	var result := Vector2(float(value[0]), float(value[1]))
	return result if is_finite(result.x) and is_finite(result.y) else null


static func _as_vector(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO


static func _is_number(value: Variant) -> bool:
	return value is int or value is float


static func _positive_finite(value: Variant) -> bool:
	return _is_number(value) and is_finite(float(value)) and float(value) > 0.0


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message, "value": {}}


static func _preset_failure(message: String) -> Dictionary:
	return {"ok": false, "error": message, "warnings": [], "preset": {}}
