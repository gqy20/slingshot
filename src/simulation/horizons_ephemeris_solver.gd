class_name SlingshotHorizonsEphemerisSolver
extends RefCounted


static func simulate(
	ephemeris_path: String,
	tick_rate: int,
	duration_sec: float,
	window_start_jd: float,
	window_end_jd: float
) -> Dictionary:
	if not FileAccess.file_exists(ephemeris_path):
		return {"error": "ephemeris not found: %s" % ephemeris_path}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ephemeris_path))
	if not parsed is Dictionary:
		return {"error": "ephemeris must be a JSON object"}
	var ephemeris: Dictionary = parsed
	var asteroid_rows: Array = ephemeris.get("asteroid", {}).get("rows", [])
	var earth_rows: Array = ephemeris.get("earth", {}).get("rows", [])
	if asteroid_rows.size() < 2 or asteroid_rows.size() != earth_rows.size():
		return {"error": "ephemeris row counts are invalid"}
	var source_start_jd := float(asteroid_rows[0][0])
	var source_end_jd := float(asteroid_rows[-1][0])
	var start_jd := clampf(window_start_jd, source_start_jd, source_end_jd)
	var end_jd := clampf(window_end_jd, start_jd, source_end_jd)
	if end_jd <= start_jd:
		return {"error": "ephemeris window must have positive duration"}
	var frame_count := maxi(2, int(round(duration_sec * tick_rate)) + 1)
	var frames: Array = []
	var path_points: Array = []
	var min_relative := INF
	var max_relative := 0.0
	var relative_sum := 0.0

	for index in range(frame_count):
		var progress := float(index) / float(frame_count - 1)
		var jd := lerpf(start_jd, end_jd, progress)
		var asteroid := _sample_rows(asteroid_rows, jd)
		var earth := _sample_rows(earth_rows, jd)
		var asteroid_position: Vector3 = asteroid["position"]
		var asteroid_velocity: Vector3 = asteroid["velocity"]
		var earth_position: Vector3 = earth["position"]
		var earth_velocity: Vector3 = earth["velocity"]
		var asteroid_xy := Vector2(asteroid_position.x, asteroid_position.y)
		var earth_xy := Vector2(earth_position.x, earth_position.y)
		var relative_xy := asteroid_xy - earth_xy
		var earth_angle := earth_xy.angle()
		var rotating_xy := relative_xy.rotated(-earth_angle)
		var relative_distance := asteroid_position.distance_to(earth_position)
		min_relative = minf(min_relative, relative_distance)
		max_relative = maxf(max_relative, relative_distance)
		relative_sum += relative_distance
		var time_sec := progress * duration_sec
		var frame := {
			"time_sec": time_sec,
			"source_jd": jd,
			"earth_position_au": earth_xy,
			"earth_z_au": earth_position.z,
			"earth_velocity_au_y": Vector2(earth_velocity.x, earth_velocity.y) * 365.25,
			"asteroid_position_au": asteroid_xy,
			"asteroid_z_au": asteroid_position.z,
			"asteroid_velocity_au_y": Vector2(asteroid_velocity.x, asteroid_velocity.y) * 365.25,
			"relative_inertial_au": relative_xy,
			"relative_rotating_au": rotating_xy,
			"relative_z_au": asteroid_position.z - earth_position.z,
			"relative_distance_au": relative_distance,
			"solar_distance_au": asteroid_position.length(),
			"orbital_speed_au_y": asteroid_velocity.length() * 365.25,
			"earth_angle_rad": earth_angle,
			"bird_position_px": asteroid_xy * 300.0,
			"bird_rotation": Vector2(asteroid_velocity.x, asteroid_velocity.y).angle(),
			"bird_velocity_px_s": Vector2(asteroid_velocity.x, asteroid_velocity.y) * 109575.0,
			"target_position_px": earth_xy * 300.0,
			"target_rotation": earth_angle,
			"target_velocity_px_s": Vector2(earth_velocity.x, earth_velocity.y) * 109575.0,
		}
		frames.append(frame)
		path_points.append(frame["bird_position_px"])

	var start_relative: Vector2 = frames[0]["relative_rotating_au"]
	var end_relative: Vector2 = frames[-1]["relative_rotating_au"]
	return {
		"model_kind": "jpl_horizons_ephemeris_ecliptic_projection",
		"authoritative_ephemeris": true,
		"tick_rate": tick_rate,
		"duration_sec": duration_sec,
		"source_start_jd": start_jd,
		"source_end_jd": end_jd,
		"source_manifest": {
			"id": ephemeris.get("id", ""),
			"generated_at_utc": ephemeris.get("generated_at_utc", ""),
			"source": ephemeris.get("source", {}).duplicate(true),
			"asteroid_raw_response_sha256": ephemeris.get("asteroid", {}).get("raw_response_sha256", ""),
			"earth_raw_response_sha256": ephemeris.get("earth", {}).get("raw_response_sha256", ""),
		},
		"frames": frames,
		"events": [],
		"path_points_px": path_points,
		"metrics": {
			"loop_closure_au": start_relative.distance_to(end_relative),
			"period_ratio": 1.0,
			"min_relative_distance_au": min_relative,
			"max_relative_distance_au": max_relative,
			"mean_relative_distance_au": relative_sum / float(frame_count),
		},
	}


static func _sample_rows(rows: Array, jd: float) -> Dictionary:
	var first_jd := float(rows[0][0])
	var last_jd := float(rows[-1][0])
	var normalized := clampf((jd - first_jd) / maxf(0.000001, last_jd - first_jd), 0.0, 1.0)
	var approximate := normalized * float(rows.size() - 1)
	var lower_index := clampi(int(floor(approximate)), 0, rows.size() - 2)
	while lower_index > 0 and float(rows[lower_index][0]) > jd:
		lower_index -= 1
	while lower_index < rows.size() - 2 and float(rows[lower_index + 1][0]) < jd:
		lower_index += 1
	var lower: Array = rows[lower_index]
	var upper: Array = rows[lower_index + 1]
	var weight := clampf(
		(jd - float(lower[0])) / maxf(0.000001, float(upper[0]) - float(lower[0])),
		0.0,
		1.0
	)
	return {
		"position": Vector3(float(lower[2]), float(lower[3]), float(lower[4])).lerp(
			Vector3(float(upper[2]), float(upper[3]), float(upper[4])), weight
		),
		"velocity": Vector3(float(lower[5]), float(lower[6]), float(lower[7])).lerp(
			Vector3(float(upper[5]), float(upper[6]), float(upper[7])), weight
		),
	}
