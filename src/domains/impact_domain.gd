class_name SlingshotImpactDomain
extends RefCounted

const ReplayTrack = preload("res://src/playback/replay_track.gd")
const Canvas = preload("res://src/video/canvases/impact_canvas.gd")
const ImpactPulseSolver = preload("res://src/simulation/impact_pulse_solver.gd")

const MODELS := ["impact_pulse"]


static func model_ids() -> Array[String]:
	return MODELS.duplicate()


static func supports_model(model: String) -> bool:
	return model in MODELS


static func is_offline_model(model: String) -> bool:
	return model == "impact_pulse"


static func simulate_episode(episode: Dictionary) -> Dictionary:
	var tick_rate := int(episode["simulation"]["tick_rate"])
	var duration := float(episode["simulation"]["duration_sec"])
	var sample_rate := int(episode["simulation"]["pulse_sample_rate_hz"])
	var records: Array = []
	for variant_value in episode["variants"]:
		var variant: Dictionary = variant_value
		var record := ImpactPulseSolver.simulate(
			variant["preset"], tick_rate, duration, sample_rate
		)
		record["variant_id"] = variant["id"]
		record["label"] = variant["label"]
		record["color_html"] = variant["color_html"]
		records.append(record)
		print(
			"[episode:simulate] complete=%s impulse=%.3f peak=%.3f"
			% [
				variant["id"],
				float(record["metrics"]["impulse_ns"]),
				float(record["metrics"]["peak_force_n"]),
			]
		)
	return {
		"records": records,
		"extras": {"impact_measurement": _measurement_extras(records)},
	}


static func normalize_simulation(simulation: Dictionary) -> Dictionary:
	if simulation.has("angle_scan") and simulation["angle_scan"] != {}:
		return _failure("simulation.angle_scan is only valid for projectile models")
	var sample_rate_value: Variant = simulation.get("pulse_sample_rate_hz", 10000)
	if not sample_rate_value is int and not sample_rate_value is float:
		return _failure("simulation.pulse_sample_rate_hz must be numeric")
	var sample_rate := int(sample_rate_value)
	if sample_rate < 100 or sample_rate > 1000000:
		return _failure("simulation.pulse_sample_rate_hz must be between 100 and 1000000")
	var normalized := simulation.duplicate(true)
	normalized.erase("angle_scan")
	normalized["pulse_sample_rate_hz"] = sample_rate
	return {"ok": true, "error": "", "value": normalized}


static func validate_record(record: Dictionary) -> String:
	var common_error := _validate_common_record(record)
	if not common_error.is_empty():
		return common_error
	if not record.get("force_curve") is Array or record["force_curve"].is_empty():
		return "record.force_curve must be a non-empty array"
	for metric in ["impulse_ns", "peak_force_n", "contact_duration_sec"]:
		if not _is_number(record["metrics"].get(metric)):
			return "record.metrics.%s must be numeric" % metric
	return ""


static func sample(record: Dictionary, time_sec: float) -> Dictionary:
	return ReplayTrack.sample(record, time_sec)


static func canvas_script() -> Script:
	return Canvas


static func _measurement_extras(records: Array) -> Dictionary:
	if records.is_empty():
		return {}
	var hard: Dictionary = records[0]
	var curve: Array = hard.get("force_curve", [])
	var contact_start := 0.012
	var rates := [10000.0, 1000.0, 100.0, 30.0]
	var sampled: Array = []
	for rate in rates:
		sampled.append({
			"rate_hz": rate,
			"peak_force_n": ImpactPulseSolver.sampled_peak(
				curve, contact_start, rate, 0.0
			),
		})
	return {"contact_start_sec": contact_start, "sampled_peaks": sampled}


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
	return ""


static func _is_number(value: Variant) -> bool:
	return value is int or value is float


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message, "value": {}}
