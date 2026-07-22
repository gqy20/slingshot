class_name SlingshotPresetLoader
extends RefCounted

const REQUIRED_VIDEO := {"width": 1920, "height": 1080, "fps": 60}
const PHYSICS_KEYS := [
	"pixels_per_meter",
	"gravity_mps2",
	"bird_mass_kg",
	"target_mass_kg",
	"spring_k_npm",
	"stretch_m",
	"efficiency",
	"launch_angle_deg",
]
const COLOR_KEYS := ["bird_color", "accent_color", "target_color"]
const COORDINATE_KEYS := ["launch_position_m", "target_position_m"]
const TOP_LEVEL_KEYS := ["id", "seed", "duration_sec", "video", "physics", "scene"]


static func load_path(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _failure("preset not found: %s" % path)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return _failure("preset is not a JSON object: %s" % path)
	return validate_dict(parsed)


static func validate_dict(raw: Dictionary) -> Dictionary:
	var warnings: Array[String] = []
	for key in raw:
		if not key in TOP_LEVEL_KEYS:
			warnings.append("unknown top-level key: %s" % key)

	if not raw.has("id") or not raw["id"] is String or raw["id"].strip_edges().is_empty():
		return _failure("id must be a non-empty string", warnings)
	if not _is_number(raw.get("duration_sec")):
		return _failure("duration_sec must be numeric", warnings)
	var duration_sec := float(raw["duration_sec"])
	if not is_finite(duration_sec) or duration_sec < 1.0 or duration_sec > 120.0:
		return _failure("duration_sec must be between 1 and 120", warnings)

	var video_value: Variant = raw.get("video")
	if not video_value is Dictionary:
		return _failure("video must be an object", warnings)
	var video: Dictionary = video_value
	for key in REQUIRED_VIDEO:
		if not _is_number(video.get(key)) or int(video[key]) != REQUIRED_VIDEO[key]:
			return _failure("video.%s must equal %d" % [key, REQUIRED_VIDEO[key]], warnings)

	var physics_value: Variant = raw.get("physics")
	if not physics_value is Dictionary:
		return _failure("physics must be an object", warnings)
	var physics: Dictionary = physics_value.duplicate(true)
	for key in PHYSICS_KEYS:
		if not _is_number(physics.get(key)):
			return _failure("physics.%s must be numeric" % key, warnings)
		physics[key] = float(physics[key])
		if not is_finite(physics[key]):
			return _failure("physics.%s must be finite" % key, warnings)
	for key in [
		"pixels_per_meter",
		"gravity_mps2",
		"bird_mass_kg",
		"target_mass_kg",
		"spring_k_npm",
		"stretch_m",
	]:
		if physics[key] <= 0.0:
			return _failure("physics.%s must be positive" % key, warnings)
	if physics["efficiency"] <= 0.0 or physics["efficiency"] > 1.0:
		return _failure("physics.efficiency must be in (0, 1]", warnings)
	if physics["launch_angle_deg"] <= 0.0 or physics["launch_angle_deg"] >= 90.0:
		return _failure("physics.launch_angle_deg must be between 0 and 90", warnings)

	var scene_value: Variant = raw.get("scene")
	if not scene_value is Dictionary:
		return _failure("scene must be an object", warnings)
	var scene: Dictionary = scene_value.duplicate(true)
	if not _is_number(scene.get("ground_y_m")) or not is_finite(float(scene["ground_y_m"])):
		return _failure("scene.ground_y_m must be finite and numeric", warnings)
	scene["ground_y_m"] = float(scene["ground_y_m"])
	for key in COORDINATE_KEYS:
		var normalized: Variant = _coordinate(scene.get(key))
		if normalized == null:
			return _failure("scene.%s must contain two finite numbers" % key, warnings)
		scene[key] = normalized
	for key in COLOR_KEYS:
		var normalized_color: Variant = _color(scene.get(key))
		if normalized_color == null:
			return _failure("scene.%s must be a valid HTML color" % key, warnings)
		scene[key] = normalized_color

	var normalized_preset := {
		"id": raw["id"].strip_edges(),
		"seed": int(raw.get("seed", 1)),
		"duration_sec": duration_sec,
		"video": REQUIRED_VIDEO.duplicate(true),
		"physics": physics,
		"scene": scene,
	}
	return {"ok": true, "error": "", "warnings": warnings, "preset": normalized_preset}


static func _is_number(value: Variant) -> bool:
	return value is int or value is float


static func _coordinate(value: Variant) -> Variant:
	if not value is Array or value.size() != 2:
		return null
	if not _is_number(value[0]) or not _is_number(value[1]):
		return null
	var result := Vector2(float(value[0]), float(value[1]))
	if not is_finite(result.x) or not is_finite(result.y):
		return null
	return result


static func _color(value: Variant) -> Variant:
	if not value is String:
		return null
	var sentinel := Color(-1.0, -1.0, -1.0, -1.0)
	var result := Color.from_string(value, sentinel)
	return null if result == sentinel else result


static func _failure(message: String, warnings: Array[String] = []) -> Dictionary:
	return {"ok": false, "error": message, "warnings": warnings, "preset": {}}
