class_name ShotModel
extends RefCounted


static func spring_energy(stiffness_npm: float, stretch_m: float) -> float:
	if stiffness_npm <= 0.0 or stretch_m < 0.0:
		return NAN
	return 0.5 * stiffness_npm * stretch_m * stretch_m


static func launch_speed(
	stiffness_npm: float,
	stretch_m: float,
	mass_kg: float,
	efficiency: float
) -> float:
	if stiffness_npm <= 0.0 or stretch_m < 0.0 or mass_kg <= 0.0:
		return NAN
	if efficiency <= 0.0 or efficiency > 1.0:
		return NAN
	return stretch_m * sqrt(efficiency * stiffness_npm / mass_kg)


static func launch_velocity(speed_mps: float, angle_deg: float) -> Vector2:
	var angle_rad := deg_to_rad(angle_deg)
	return Vector2(cos(angle_rad), -sin(angle_rad)) * speed_mps


static func projectile_position(
	start_m: Vector2,
	initial_velocity_mps: Vector2,
	gravity_mps2: float,
	time_sec: float
) -> Vector2:
	return start_m + initial_velocity_mps * time_sec + Vector2(0.0, 0.5 * gravity_mps2 * time_sec * time_sec)


static func kinetic_energy(mass_kg: float, velocity_mps: Vector2) -> float:
	if mass_kg <= 0.0:
		return NAN
	return 0.5 * mass_kg * velocity_mps.length_squared()


static func rotational_energy(inertia_kg_m2: float, angular_velocity_rad_s: float) -> float:
	if inertia_kg_m2 < 0.0:
		return NAN
	return 0.5 * inertia_kg_m2 * angular_velocity_rad_s * angular_velocity_rad_s


static func momentum(mass_kg: float, velocity_mps: Vector2) -> Vector2:
	return velocity_mps * mass_kg


static func impulse(mass_kg: float, before_mps: Vector2, after_mps: Vector2) -> Vector2:
	return mass_kg * (after_mps - before_mps)


static func average_force(impulse_ns: Vector2, sample_time_sec: float) -> float:
	if sample_time_sec <= 0.0:
		return NAN
	return impulse_ns.length() / sample_time_sec


static func meters_to_pixels(value_m: Vector2, pixels_per_meter: float) -> Vector2:
	if pixels_per_meter <= 0.0:
		return Vector2(INF, INF)
	return value_m * pixels_per_meter


static func pixels_to_meters(value_px: Vector2, pixels_per_meter: float) -> Vector2:
	if pixels_per_meter <= 0.0:
		return Vector2(INF, INF)
	return value_px / pixels_per_meter


static func velocity_px_to_mps(value_px_s: Vector2, pixels_per_meter: float) -> Vector2:
	return pixels_to_meters(value_px_s, pixels_per_meter)
