class_name ProjectileDragSolver
extends RefCounted

const ShotModel = preload("res://src/core/shot_model.gd")


static func simulate(preset: Dictionary, tick_rate: int, max_duration_sec: float) -> Dictionary:
	var physics: Dictionary = preset["physics"]
	var scene: Dictionary = preset["scene"]
	var dt := 1.0 / float(maxi(1, tick_rate))
	var ppm := float(physics["pixels_per_meter"])
	var mass := float(physics["bird_mass_kg"])
	var ground_y := float(scene.get("landing_y_m", scene["ground_y_m"]))
	var position := Vector2(scene["launch_position_m"])
	var launch_position := position
	var speed := float(physics.get("launch_speed_mps", 0.0))
	if speed <= 0.0:
		speed = ShotModel.launch_speed(
			float(physics["spring_k_npm"]),
			float(physics["stretch_m"]),
			mass,
			float(physics["efficiency"])
		)
	var velocity := ShotModel.launch_velocity(speed, float(physics["launch_angle_deg"]))
	var target_position := Vector2(scene["target_position_m"]) * ppm
	var frames: Array = []
	var elapsed := 0.0
	var max_height := maxf(0.0, ground_y - position.y)
	var dissipated_energy := 0.0
	var landed := false
	_capture_frame(
		frames, physics, position, velocity, target_position, elapsed, ground_y, dissipated_energy
	)

	while elapsed + 0.5 * dt < max_duration_sec and not landed:
		var next := _rk4_step(position, velocity, dt, physics)
		var next_position: Vector2 = next["position_m"]
		var next_velocity: Vector2 = next["velocity_mps"]
		var step_drag_power := maxf(0.0, -_drag_force(velocity, physics).dot(
			velocity - _wind(physics)
		))
		var next_drag_power := maxf(0.0, -_drag_force(next_velocity, physics).dot(
			next_velocity - _wind(physics)
		))
		dissipated_energy += 0.5 * (step_drag_power + next_drag_power) * dt
		var next_elapsed := elapsed + dt

		if position.y < ground_y and next_position.y >= ground_y:
			var denominator := next_position.y - position.y
			var weight := 1.0 if absf(denominator) < 1e-9 else (ground_y - position.y) / denominator
			weight = clampf(weight, 0.0, 1.0)
			next_position = position.lerp(next_position, weight)
			next_position.y = ground_y
			next_velocity = velocity.lerp(next_velocity, weight)
			next_elapsed = elapsed + dt * weight
			landed = true

		position = next_position
		velocity = next_velocity
		elapsed = next_elapsed
		max_height = maxf(max_height, ground_y - position.y)
		_capture_frame(
			frames, physics, position, velocity, target_position, elapsed, ground_y,
			dissipated_energy
		)

	var range_m := maxf(0.0, position.x - launch_position.x)
	var events: Array = [{"type": "launch", "time_sec": 0.0}]
	if landed:
		events.append({
			"type": "first_ground_contact",
			"time_sec": elapsed,
			"range_m": range_m,
		})
	return {
		"tick_rate": tick_rate,
		"duration_sec": max_duration_sec,
		"frames": frames,
		"events": events,
		"metrics": {
			"launch_speed_mps": speed,
			"launch_angle_deg": float(physics["launch_angle_deg"]),
			"flight_range_m": range_m,
			"range_m": range_m,
			"flight_time_sec": elapsed,
			"max_height_m": max_height,
			"dissipated_energy_j": dissipated_energy,
			"ballistic_coefficient_kg_m2": _ballistic_coefficient(physics),
			"air_density_kg_m3": float(physics.get("air_density_kg_m3", 0.0)),
		},
	}


static func scan_angles(
	preset: Dictionary,
	tick_rate: int,
	max_duration_sec: float,
	min_angle_deg: float,
	max_angle_deg: float,
	step_deg: float
) -> Array:
	var points: Array = []
	var angle := min_angle_deg
	while angle <= max_angle_deg + step_deg * 0.25:
		var scan_preset := preset.duplicate(true)
		scan_preset["physics"]["launch_angle_deg"] = minf(angle, max_angle_deg)
		var result := simulate(scan_preset, tick_rate, max_duration_sec)
		points.append({
			"angle_deg": float(scan_preset["physics"]["launch_angle_deg"]),
			"range_m": float(result["metrics"]["flight_range_m"]),
		})
		angle += step_deg
	return points


static func best_point(points: Array) -> Dictionary:
	var best: Dictionary = {}
	for point_value in points:
		var point: Dictionary = point_value
		if best.is_empty() or float(point["range_m"]) > float(best["range_m"]):
			best = point.duplicate(true)
	return best


static func _rk4_step(
	position: Vector2,
	velocity: Vector2,
	dt: float,
	physics: Dictionary
) -> Dictionary:
	var k1_position := velocity
	var k1_velocity := _acceleration(velocity, physics)
	var k2_position := velocity + k1_velocity * dt * 0.5
	var k2_velocity := _acceleration(velocity + k1_velocity * dt * 0.5, physics)
	var k3_position := velocity + k2_velocity * dt * 0.5
	var k3_velocity := _acceleration(velocity + k2_velocity * dt * 0.5, physics)
	var k4_position := velocity + k3_velocity * dt
	var k4_velocity := _acceleration(velocity + k3_velocity * dt, physics)
	return {
		"position_m": position + dt / 6.0 * (
			k1_position + 2.0 * k2_position + 2.0 * k3_position + k4_position
		),
		"velocity_mps": velocity + dt / 6.0 * (
			k1_velocity + 2.0 * k2_velocity + 2.0 * k3_velocity + k4_velocity
		),
	}


static func _acceleration(velocity_mps: Vector2, physics: Dictionary) -> Vector2:
	return (
		Vector2(0.0, float(physics["gravity_mps2"]))
		+ _drag_force(velocity_mps, physics) / float(physics["bird_mass_kg"])
	)


static func _drag_force(velocity_mps: Vector2, physics: Dictionary) -> Vector2:
	var relative_velocity := velocity_mps - _wind(physics)
	var speed := relative_velocity.length()
	if speed <= 1e-9:
		return Vector2.ZERO
	var area := PI * pow(float(physics.get("projectile_radius_m", 0.05)), 2.0)
	var coefficient := (
		0.5
		* float(physics.get("air_density_kg_m3", 0.0))
		* float(physics.get("drag_coefficient", 0.0))
		* area
	)
	return -coefficient * speed * relative_velocity


static func _wind(physics: Dictionary) -> Vector2:
	return Vector2(
		float(physics.get("wind_x_mps", 0.0)),
		float(physics.get("wind_y_mps", 0.0))
	)


static func _ballistic_coefficient(physics: Dictionary) -> float:
	var area := PI * pow(float(physics.get("projectile_radius_m", 0.05)), 2.0)
	var denominator := float(physics.get("drag_coefficient", 0.0)) * area
	return INF if denominator <= 0.0 else float(physics["bird_mass_kg"]) / denominator


static func _capture_frame(
	frames: Array,
	physics: Dictionary,
	position_m: Vector2,
	velocity_mps: Vector2,
	target_position_px: Vector2,
	time_sec: float,
	ground_y_m: float,
	dissipated_energy_j: float
) -> void:
	var ppm := float(physics["pixels_per_meter"])
	var mass := float(physics["bird_mass_kg"])
	var drag_force := _drag_force(velocity_mps, physics)
	var potential := mass * float(physics["gravity_mps2"]) * maxf(0.0, ground_y_m - position_m.y)
	frames.append({
		"time_sec": time_sec,
		"position_m": position_m,
		"velocity_mps": velocity_mps,
		"drag_force_n": drag_force,
		"drag_power_w": maxf(0.0, -drag_force.dot(velocity_mps - _wind(physics))),
		"kinetic_energy_j": ShotModel.kinetic_energy(mass, velocity_mps),
		"potential_energy_j": potential,
		"dissipated_energy_j": dissipated_energy_j,
		"bird_position_px": position_m * ppm,
		"bird_rotation": velocity_mps.angle(),
		"bird_velocity_px_s": velocity_mps * ppm,
		"target_position_px": target_position_px,
		"target_rotation": 0.0,
		"target_velocity_px_s": Vector2.ZERO,
	})
