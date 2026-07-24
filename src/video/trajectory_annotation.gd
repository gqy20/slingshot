class_name SlingshotTrajectoryAnnotation
extends RefCounted

const ReplayTrack = preload("res://src/playback/replay_track.gd")


static func initial_geometry(record: Dictionary) -> Dictionary:
	var state := ReplayTrack.sample(record, 0.0)
	if state.is_empty():
		return {}
	var velocity: Vector2 = state["bird_velocity_px_s"]
	if velocity.length_squared() <= 0.0001:
		return {}
	return {
		"origin": Vector2(state["bird_position_px"]),
		"velocity": velocity,
		"direction": velocity.normalized(),
		"angle_deg": rad_to_deg(atan2(-velocity.y, velocity.x)),
	}


static func trajectory_alignment(record: Dictionary) -> float:
	var geometry := initial_geometry(record)
	var tick_rate := maxi(1, int(record.get("tick_rate", 120)))
	var next_state := ReplayTrack.sample(record, 1.0 / float(tick_rate))
	if geometry.is_empty() or next_state.is_empty():
		return -1.0
	var tangent := (
		Vector2(next_state["bird_position_px"])
		- Vector2(geometry["origin"])
	).normalized()
	return tangent.dot(Vector2(geometry["direction"]))


static func flight_time_sec(record: Dictionary) -> float:
	var event_time := ReplayTrack.event_time(record, "first_ground_contact")
	if event_time >= 0.0:
		return event_time
	var metrics: Dictionary = record.get("metrics", {})
	return float(metrics.get("flight_time_sec", record.get("duration_sec", 0.0)))
