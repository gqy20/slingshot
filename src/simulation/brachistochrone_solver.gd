class_name SlingshotBrachistochroneSolver
extends RefCounted

const MIN_DEPTH_M := 1.0e-9


static func simulate(
	preset: Dictionary,
	tick_rate: int,
	duration_sec: float,
	integration_steps: int = 8000
) -> Dictionary:
	var physics: Dictionary = preset["physics"]
	var scene: Dictionary = preset["scene"]
	var gravity := float(physics["gravity_mps2"])
	var mass := float(physics["mass_kg"])
	var ppm := float(physics["pixels_per_meter"])
	var width := float(scene["horizontal_span_m"])
	var drop := float(scene["vertical_drop_m"])
	var kind := String(scene["track_kind"])
	var origin: Vector2 = scene["origin_px"]
	var path_parameters := _path_parameters(kind, width, drop)
	var table := _build_table(
		kind, width, drop, gravity, integration_steps, path_parameters
	)
	var arrival_time := float(table[-1]["time_sec"])
	var path_length := float(table[-1]["distance_m"])
	var arrival_speed := sqrt(2.0 * gravity * drop)
	var frames: Array = []
	var frame_count := roundi(duration_sec * tick_rate) + 1
	var initial_energy := 0.0
	var max_energy_error := 0.0
	for frame_index in range(frame_count):
		var time_sec := float(frame_index) / float(tick_rate)
		var state := _state_at_time(table, minf(time_sec, arrival_time))
		var position_m: Vector2 = state["position_m"]
		var path_speed := sqrt(2.0 * gravity * maxf(0.0, position_m.y))
		var arrived := time_sec >= arrival_time
		var speed := 0.0 if arrived else path_speed
		var kinetic := 0.5 * mass * path_speed * path_speed
		var potential := -mass * gravity * position_m.y
		if not arrived:
			max_energy_error = maxf(
				max_energy_error, absf(kinetic + potential - initial_energy)
			)
		frames.append({
			"time_sec": time_sec,
			"elapsed_motion_sec": minf(time_sec, arrival_time),
			"position_px": origin + position_m * ppm,
			"position_m": position_m,
			"height_drop_m": position_m.y,
			"distance_traveled_m": float(state["distance_m"]),
			"speed_mps": speed,
			"path_speed_mps": path_speed,
			"kinetic_energy_j": kinetic,
			"potential_energy_j": potential,
			"progress": float(state["progress"]),
			"arrived": arrived,
		})
	var path_points_px: Array = []
	var preview_steps := 240
	for index in range(preview_steps + 1):
		path_points_px.append(
			origin + _path_point(
				kind, float(index) / float(preview_steps), width, drop, path_parameters
			) * ppm
		)
	var path_segments := _build_path_segments(table, origin, ppm, 48)
	return {
		"tick_rate": tick_rate,
		"duration_sec": duration_sec,
		"frames": frames,
		"events": [
			{"type": "release", "time_sec": 0.0},
			{"type": "arrival", "time_sec": arrival_time},
		],
		"path_points_px": path_points_px,
		"path_segments": path_segments,
		"metrics": {
			"arrival_time_sec": arrival_time,
			"arrival_speed_mps": arrival_speed,
			"path_length_m": path_length,
			"max_speed_mps": arrival_speed,
			"max_energy_error_j": max_energy_error,
			"integration_steps": integration_steps,
		},
	}


static func _build_path_segments(
	table: Array,
	origin: Vector2,
	ppm: float,
	segment_count: int
) -> Array:
	var segments: Array = []
	var last_index := table.size() - 1
	for segment_index in range(segment_count):
		var start_index := roundi(float(segment_index) / float(segment_count) * last_index)
		var end_index := roundi(float(segment_index + 1) / float(segment_count) * last_index)
		if end_index <= start_index:
			continue
		var start: Dictionary = table[start_index]
		var finish: Dictionary = table[end_index]
		var segment_time := float(finish["time_sec"]) - float(start["time_sec"])
		var segment_length := float(finish["distance_m"]) - float(start["distance_m"])
		segments.append({
			"start_px": origin + Vector2(start["position_m"]) * ppm,
			"finish_px": origin + Vector2(finish["position_m"]) * ppm,
			"start_time_sec": float(start["time_sec"]),
			"finish_time_sec": float(finish["time_sec"]),
			"segment_time_sec": segment_time,
			"segment_length_m": segment_length,
			"mean_speed_mps": segment_length / maxf(segment_time, 1.0e-12),
		})
	return segments


static func cycloid_exact_arrival_time(width: float, drop: float, gravity: float) -> float:
	var theta_end := _cycloid_theta_end(width / drop)
	var radius := drop / (1.0 - cos(theta_end))
	return sqrt(radius / gravity) * theta_end


static func _build_table(
	kind: String,
	width: float,
	drop: float,
	gravity: float,
	steps: int,
	path_parameters: Dictionary
) -> Array:
	var table: Array = [{
		"progress": 0.0,
		"position_m": Vector2.ZERO,
		"distance_m": 0.0,
		"time_sec": 0.0,
	}]
	var previous := Vector2.ZERO
	var cumulative_distance := 0.0
	var cumulative_time := 0.0
	for index in range(1, steps + 1):
		var progress := float(index) / float(steps)
		var position := _path_point(kind, progress, width, drop, path_parameters)
		var midpoint := _path_point(
			kind, (float(index) - 0.5) / float(steps), width, drop, path_parameters
		)
		var segment_length := previous.distance_to(position)
		var midpoint_speed := sqrt(2.0 * gravity * maxf(MIN_DEPTH_M, midpoint.y))
		cumulative_distance += segment_length
		cumulative_time += segment_length / midpoint_speed
		table.append({
			"progress": progress,
			"position_m": position,
			"distance_m": cumulative_distance,
			"time_sec": cumulative_time,
		})
		previous = position
	return table


static func _state_at_time(table: Array, time_sec: float) -> Dictionary:
	if time_sec <= 0.0:
		return table[0]
	if time_sec >= float(table[-1]["time_sec"]):
		return table[-1]
	var low := 0
	var high := table.size() - 1
	while high - low > 1:
		var middle := (low + high) >> 1
		if float(table[middle]["time_sec"]) <= time_sec:
			low = middle
		else:
			high = middle
	var before: Dictionary = table[low]
	var after: Dictionary = table[high]
	var span := maxf(1.0e-12, float(after["time_sec"]) - float(before["time_sec"]))
	var weight := clampf((time_sec - float(before["time_sec"])) / span, 0.0, 1.0)
	return {
		"progress": lerpf(float(before["progress"]), float(after["progress"]), weight),
		"position_m": Vector2(before["position_m"]).lerp(Vector2(after["position_m"]), weight),
		"distance_m": lerpf(float(before["distance_m"]), float(after["distance_m"]), weight),
		"time_sec": time_sec,
	}


static func _path_parameters(kind: String, width: float, drop: float) -> Dictionary:
	match kind:
		"cycloid":
			var theta_end := _cycloid_theta_end(width / drop)
			return {
				"theta_end": theta_end,
				"radius": drop / (1.0 - cos(theta_end)),
			}
		"circular_arc":
			var radius := (width * width + drop * drop) / (2.0 * width)
			return {
				"radius": radius,
				"finish_angle": atan2(drop, width - radius),
			}
	return {}


static func _path_point(
	kind: String,
	progress: float,
	width: float,
	drop: float,
	parameters: Dictionary = {}
) -> Vector2:
	var u := clampf(progress, 0.0, 1.0)
	match kind:
		"cycloid":
			var theta_end := float(parameters["theta_end"])
			var radius := float(parameters["radius"])
			var theta := theta_end * u
			return Vector2(
				radius * (theta - sin(theta)),
				radius * (1.0 - cos(theta))
			)
		"circular_arc":
			var radius := float(parameters["radius"])
			var finish_angle := float(parameters["finish_angle"])
			var angle := lerpf(PI, finish_angle, u)
			return Vector2(radius + radius * cos(angle), radius * sin(angle))
		_:
			return Vector2(width * u, drop * u)


static func _cycloid_theta_end(target_ratio: float) -> float:
	var low := 1.0e-5
	var high := TAU - 1.0e-5
	for _iteration in range(96):
		var middle := 0.5 * (low + high)
		var ratio := (middle - sin(middle)) / (1.0 - cos(middle))
		if ratio < target_ratio:
			low = middle
		else:
			high = middle
	return 0.5 * (low + high)
