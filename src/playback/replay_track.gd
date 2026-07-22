class_name SlingshotReplayTrack
extends RefCounted


static func sample(record: Dictionary, time_sec: float) -> Dictionary:
	var frames_value: Variant = record.get("frames", [])
	if not frames_value is Array or frames_value.is_empty():
		return {}
	var frames: Array = frames_value
	var tick_rate := maxi(1, int(record.get("tick_rate", 120)))
	var position := clampf(time_sec, 0.0, float(record.get("duration_sec", 0.0))) * tick_rate
	var lower_index := clampi(int(floor(position)), 0, frames.size() - 1)
	var upper_index := mini(lower_index + 1, frames.size() - 1)
	var weight := clampf(position - floor(position), 0.0, 1.0)
	var lower: Dictionary = frames[lower_index]
	var upper: Dictionary = frames[upper_index]
	return {
		"bird_position_px": _vector(lower["bird_position_px"]).lerp(
			_vector(upper["bird_position_px"]), weight
		),
		"bird_rotation": lerp_angle(
			float(lower["bird_rotation"]), float(upper["bird_rotation"]), weight
		),
		"bird_velocity_px_s": _vector(lower["bird_velocity_px_s"]).lerp(
			_vector(upper["bird_velocity_px_s"]), weight
		),
		"target_position_px": _vector(lower["target_position_px"]).lerp(
			_vector(upper["target_position_px"]), weight
		),
		"target_rotation": lerp_angle(
			float(lower["target_rotation"]), float(upper["target_rotation"]), weight
		),
		"target_velocity_px_s": _vector(lower["target_velocity_px_s"]).lerp(
			_vector(upper["target_velocity_px_s"]), weight
		),
	}


static func event_time(record: Dictionary, event_type: String) -> float:
	for event_value in record.get("events", []):
		if event_value is Dictionary and event_value.get("type") == event_type:
			return float(event_value.get("time_sec", -1.0))
	return -1.0


static func partial_trajectory(record: Dictionary, time_sec: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	var tick_rate := maxi(1, int(record.get("tick_rate", 120)))
	var last_index := clampi(
		int(ceil(time_sec * tick_rate)),
		0,
		maxi(0, record.get("frames", []).size() - 1)
	)
	for index in range(0, last_index + 1, 3):
		result.append(_vector(record["frames"][index]["bird_position_px"]))
	return result


static func full_trajectory(record: Dictionary) -> PackedVector2Array:
	var result := PackedVector2Array()
	for index in range(0, record.get("frames", []).size(), 3):
		result.append(_vector(record["frames"][index]["bird_position_px"]))
	return result


static func _vector(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO
