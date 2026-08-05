class_name SlingshotQuasiSatelliteSolver
extends RefCounted

const TAU_F := TAU


static func simulate(preset: Dictionary, tick_rate: int, duration_sec: float) -> Dictionary:
	var scene: Dictionary = preset["scene"]
	var earth_period_years := float(preset["physics"]["orbital_period_years"])
	var period_ratio := float(scene["period_ratio"])
	var analytic_year_span := float(scene.get("analytic_year_span", 1.0))
	var asteroid_period_years := earth_period_years * period_ratio
	var eccentricity := float(scene["eccentricity"])
	var semi_major_axis := float(scene["semi_major_axis_au"])
	var phase_offset := float(scene["phase_offset_rad"])
	var periapsis_angle := float(scene["periapsis_angle_rad"])
	var frame_count := maxi(2, int(round(duration_sec * tick_rate)) + 1)
	var frames: Array = []
	var path_points: Array = []
	var min_relative := INF
	var max_relative := 0.0
	var relative_sum := 0.0

	for index in range(frame_count):
		var time_sec := minf(duration_sec, float(index) / float(tick_rate))
		var years := time_sec / duration_sec * earth_period_years * analytic_year_span
		var earth_angle := TAU_F * years / earth_period_years
		var earth_position := Vector2(cos(earth_angle), sin(earth_angle))
		var earth_velocity := Vector2(-sin(earth_angle), cos(earth_angle)) * TAU_F
		var mean_anomaly := TAU_F * years / asteroid_period_years + phase_offset
		var eccentric_anomaly := _solve_kepler(mean_anomaly, eccentricity)
		var orbital_position := Vector2(
			semi_major_axis * (cos(eccentric_anomaly) - eccentricity),
			semi_major_axis * sqrt(1.0 - eccentricity * eccentricity) * sin(eccentric_anomaly)
		)
		var asteroid_position := orbital_position.rotated(periapsis_angle)
		var d_e_dt := (TAU_F / asteroid_period_years) / maxf(
			0.0001, 1.0 - eccentricity * cos(eccentric_anomaly)
		)
		var orbital_velocity := Vector2(
			-semi_major_axis * sin(eccentric_anomaly) * d_e_dt,
			semi_major_axis * sqrt(1.0 - eccentricity * eccentricity)
				* cos(eccentric_anomaly) * d_e_dt
		)
		var asteroid_velocity := orbital_velocity.rotated(periapsis_angle)
		var relative_inertial := asteroid_position - earth_position
		var relative_rotating := relative_inertial.rotated(-earth_angle)
		var relative_distance := relative_inertial.length()
		min_relative = minf(min_relative, relative_distance)
		max_relative = maxf(max_relative, relative_distance)
		relative_sum += relative_distance
		var frame := {
			"time_sec": time_sec,
			"earth_position_au": earth_position,
			"earth_velocity_au_y": earth_velocity,
			"asteroid_position_au": asteroid_position,
			"asteroid_velocity_au_y": asteroid_velocity,
			"relative_inertial_au": relative_inertial,
			"relative_rotating_au": relative_rotating,
			"solar_distance_au": asteroid_position.length(),
			"orbital_speed_au_y": asteroid_velocity.length(),
			"earth_angle_rad": earth_angle,
			"bird_position_px": asteroid_position * 300.0,
			"bird_rotation": asteroid_velocity.angle(),
			"bird_velocity_px_s": asteroid_velocity * 300.0,
			"target_position_px": earth_position * 300.0,
			"target_rotation": earth_angle,
			"target_velocity_px_s": earth_velocity * 300.0,
		}
		frames.append(frame)
		path_points.append(frame["bird_position_px"])

	var start_relative: Vector2 = frames[0]["relative_rotating_au"]
	var end_relative: Vector2 = frames[-1]["relative_rotating_au"]
	return {
		"model_kind": "planar_sun_two_body_reference_frame_demonstration",
		"authoritative_ephemeris": false,
		"tick_rate": tick_rate,
		"duration_sec": duration_sec,
		"frames": frames,
		"events": [],
		"path_points_px": path_points,
		"metrics": {
			"loop_closure_au": start_relative.distance_to(end_relative),
			"period_ratio": period_ratio,
			"min_relative_distance_au": min_relative,
			"max_relative_distance_au": max_relative,
			"mean_relative_distance_au": relative_sum / float(frame_count),
		},
	}


static func _solve_kepler(mean_anomaly: float, eccentricity: float) -> float:
	var wrapped := fposmod(mean_anomaly + PI, TAU_F) - PI
	var eccentric_anomaly := wrapped
	for _iteration in range(10):
		var residual := eccentric_anomaly - eccentricity * sin(eccentric_anomaly) - wrapped
		var derivative := 1.0 - eccentricity * cos(eccentric_anomaly)
		eccentric_anomaly -= residual / maxf(0.0001, derivative)
	return eccentric_anomaly
