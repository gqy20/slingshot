class_name SlingshotProjectileDomain
extends RefCounted

const ReplayTrack = preload("res://src/playback/replay_track.gd")
const Canvas = preload("res://src/video/canvases/projectile_canvas.gd")
const ProjectileSolver = preload("res://src/simulation/projectile_drag_solver.gd")
const PresetLoader = preload("res://src/core/preset_loader.gd")
const EpisodeLayout = preload("res://src/video/episode_layout.gd")

const MODELS := ["rigidbody", "projectile_drag"]


static func model_ids() -> Array[String]:
	return MODELS.duplicate()


static func supports_model(model: String) -> bool:
	return model in MODELS


static func is_offline_model(model: String) -> bool:
	return model == "projectile_drag"


static func simulate_episode(episode: Dictionary) -> Dictionary:
	var tick_rate := int(episode["simulation"]["tick_rate"])
	var duration := float(episode["simulation"]["duration_sec"])
	var records: Array = []
	for variant_value in episode["variants"]:
		var variant: Dictionary = variant_value
		var record := ProjectileSolver.simulate(variant["preset"], tick_rate, duration)
		record["variant_id"] = variant["id"]
		record["label"] = variant["label"]
		record["color_html"] = variant["color_html"]
		records.append(record)
		print(
			"[episode:simulate] complete=%s range=%.3f max_height=%.3f"
			% [
				variant["id"],
				float(record["metrics"]["flight_range_m"]),
				float(record["metrics"]["max_height_m"]),
			]
		)
	return {"records": records, "extras": _angle_scans(episode, tick_rate, duration)}


static func normalize_simulation(simulation: Dictionary) -> Dictionary:
	if simulation.has("pulse_sample_rate_hz"):
		return _failure("simulation.pulse_sample_rate_hz is only valid for impact_pulse")
	var scan_result := _normalize_angle_scan(simulation.get("angle_scan", {}))
	if not scan_result["ok"]:
		return scan_result
	var normalized := simulation.duplicate(true)
	normalized["angle_scan"] = scan_result["value"]
	return {"ok": true, "error": "", "value": normalized}


static func normalize_preset(raw: Dictionary, variant_color: String) -> Dictionary:
	var colored := raw.duplicate(true)
	var scene: Dictionary = colored.get("scene", {})
	scene["bird_color"] = variant_color
	colored["scene"] = scene
	return PresetLoader.validate_dict(colored)


static func validate_record(record: Dictionary) -> String:
	var common_error := _validate_common_record(record)
	if not common_error.is_empty():
		return common_error
	for metric in ["flight_range_m", "max_height_m"]:
		if not _is_number(record["metrics"].get(metric)):
			return "record.metrics.%s must be numeric" % metric
	return ""


static func sample(record: Dictionary, time_sec: float) -> Dictionary:
	return ReplayTrack.sample(record, time_sec)


static func canvas_script() -> Script:
	return Canvas


static func audit_bundle(bundle: Dictionary) -> PackedStringArray:
	return EpisodeLayout.audit_bundle(bundle)


static func _angle_scans(episode: Dictionary, tick_rate: int, duration: float) -> Dictionary:
	var scan: Dictionary = episode["simulation"].get("angle_scan", {})
	if scan.is_empty() or episode["variants"].is_empty():
		return {}
	var base_preset: Dictionary = episode["variants"][0]["preset"].duplicate(true)
	var min_angle := float(scan["min_angle_deg"])
	var max_angle := float(scan["max_angle_deg"])
	var step := float(scan["step_deg"])
	var drag_points := ProjectileSolver.scan_angles(
		base_preset, tick_rate, duration, min_angle, max_angle, step
	)
	var range_scans: Array = [{
		"id": "air",
		"label": "有空气",
		"color_html": episode["theme"]["colors"]["accent"].to_html(false),
		"points": drag_points,
		"best": ProjectileSolver.best_point(drag_points),
	}]
	if bool(scan.get("include_vacuum", true)):
		var vacuum_preset := base_preset.duplicate(true)
		vacuum_preset["physics"]["air_density_kg_m3"] = 0.0
		var vacuum_points := ProjectileSolver.scan_angles(
			vacuum_preset, tick_rate, duration, min_angle, max_angle, step
		)
		range_scans.push_front({
			"id": "vacuum",
			"label": "理想真空",
			"color_html": episode["theme"]["colors"]["muted"].to_html(false),
			"points": vacuum_points,
			"best": ProjectileSolver.best_point(vacuum_points),
		})
	if bool(scan.get("include_parameter_variant", false)):
		var parameter_preset := base_preset.duplicate(true)
		parameter_preset["physics"]["bird_mass_kg"] = (
			float(parameter_preset["physics"]["bird_mass_kg"]) * 2.0
		)
		var parameter_points := ProjectileSolver.scan_angles(
			parameter_preset, tick_rate, duration, min_angle, max_angle, step
		)
		range_scans.append({
			"id": "higher-ballistic-coefficient",
			"label": "质量×2，同外形同速",
			"color_html": episode["theme"]["colors"]["highlight"].to_html(false),
			"points": parameter_points,
			"best": ProjectileSolver.best_point(parameter_points),
		})
	return {"range_scans": range_scans}


static func _normalize_angle_scan(value: Variant) -> Dictionary:
	if value == null or value == {}:
		return {"ok": true, "error": "", "value": {}}
	if not value is Dictionary:
		return _failure("simulation.angle_scan must be an object")
	var scan: Dictionary = value
	for key in ["min_angle_deg", "max_angle_deg", "step_deg"]:
		if not _positive_finite(scan.get(key)):
			return _failure("simulation.angle_scan.%s must be positive and finite" % key)
	var min_angle := float(scan["min_angle_deg"])
	var max_angle := float(scan["max_angle_deg"])
	var step := float(scan["step_deg"])
	if min_angle >= max_angle or max_angle >= 90.0:
		return _failure("simulation.angle_scan requires 0 < min < max < 90")
	if step > max_angle - min_angle:
		return _failure("simulation.angle_scan.step_deg is too large")
	return {
		"ok": true,
		"error": "",
		"value": {
			"min_angle_deg": min_angle,
			"max_angle_deg": max_angle,
			"step_deg": step,
			"include_vacuum": bool(scan.get("include_vacuum", true)),
			"include_parameter_variant": bool(scan.get("include_parameter_variant", false)),
		},
	}


static func _validate_common_record(record: Dictionary) -> String:
	for key in ["variant_id", "label", "color_html"]:
		if not record.get(key) is String or String(record[key]).is_empty():
			return "record.%s must be a non-empty string" % key
	if not record.get("frames") is Array or record["frames"].is_empty():
		return "record.frames must be a non-empty array"
	if not record.get("events") is Array:
		return "record.events must be an array"
	if not record.get("metrics") is Dictionary:
		return "record.metrics must be an object"
	var frame: Dictionary = record["frames"][0] if record["frames"][0] is Dictionary else {}
	for key in [
		"bird_position_px", "bird_rotation", "bird_velocity_px_s",
		"target_position_px", "target_rotation", "target_velocity_px_s",
	]:
		if not frame.has(key):
			return "record.frames[0].%s is required" % key
	return ""


static func _is_number(value: Variant) -> bool:
	return value is int or value is float


static func _positive_finite(value: Variant) -> bool:
	return _is_number(value) and is_finite(float(value)) and float(value) > 0.0


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message, "value": {}}
