class_name SlingshotImpactPulseSolver
extends RefCounted

const DEFAULT_SAMPLE_RATE_HZ := 10000


static func simulate(
	preset: Dictionary,
	tick_rate: int,
	duration_sec: float,
	sample_rate_hz: int = DEFAULT_SAMPLE_RATE_HZ
) -> Dictionary:
	var physics: Dictionary = preset["physics"]
	var scene: Dictionary = preset["scene"]
	var mass := float(physics["bird_mass_kg"])
	var incoming_speed := float(physics["launch_speed_mps"])
	var rebound_speed := float(physics["rebound_speed_mps"])
	var contact_duration := float(physics["contact_duration_sec"])
	var impulse := mass * (incoming_speed + rebound_speed)
	var average_force := impulse / contact_duration
	var peak_force := PI * impulse / (2.0 * contact_duration)
	var curve := force_curve(impulse, contact_duration, sample_rate_hz)
	var ppm := float(physics["pixels_per_meter"])
	var center := Vector2(scene["launch_position_m"]) * ppm
	var target := Vector2(scene["target_position_m"]) * ppm
	var frames: Array = []
	for frame_index in range(roundi(duration_sec * tick_rate) + 1):
		frames.append({
			"time_sec": float(frame_index) / float(tick_rate),
			"bird_position_px": center,
			"bird_rotation": 0.0,
			"bird_velocity_px_s": Vector2.ZERO,
			"target_position_px": target,
			"target_rotation": 0.0,
			"target_velocity_px_s": Vector2.ZERO,
		})
	return {
		"tick_rate": tick_rate,
		"duration_sec": duration_sec,
		"frames": frames,
		"events": [
			{"type": "launch", "time_sec": 0.0},
			{"type": "first_contact", "time_sec": 0.4, "impulse_ns": impulse},
		],
		"metrics": {
			"incoming_speed_mps": incoming_speed,
			"rebound_speed_mps": rebound_speed,
			"impulse_ns": impulse,
			"contact_duration_sec": contact_duration,
			"average_force_n": average_force,
			"peak_force_n": peak_force,
			"max_penetration_m": float(physics["max_penetration_m"]),
		},
		"force_curve": curve,
		"sample_rate_hz": sample_rate_hz,
	}


static func force_curve(impulse_ns: float, duration_sec: float, sample_rate_hz: int) -> Array:
	var sample_count := maxi(2, ceili(duration_sec * sample_rate_hz) + 1)
	var peak_force := PI * impulse_ns / (2.0 * duration_sec)
	var curve: Array = []
	var cumulative := 0.0
	var previous_force := 0.0
	var previous_time := 0.0
	for index in range(sample_count):
		var time_sec := duration_sec * float(index) / float(sample_count - 1)
		var force_n := peak_force * sin(PI * time_sec / duration_sec)
		if index > 0:
			cumulative += 0.5 * (previous_force + force_n) * (time_sec - previous_time)
		curve.append({
			"time_sec": time_sec,
			"force_n": maxf(0.0, force_n),
			"cumulative_impulse_ns": cumulative,
		})
		previous_force = force_n
		previous_time = time_sec
	return curve


static func sampled_peak(
	curve: Array,
	contact_start_sec: float,
	sample_rate_hz: float,
	phase_sec: float = 0.0
) -> float:
	if curve.is_empty() or sample_rate_hz <= 0.0:
		return 0.0
	var duration := float(curve[-1]["time_sec"])
	var finish := contact_start_sec + duration
	var interval := 1.0 / sample_rate_hz
	var sample_time := phase_sec
	while sample_time < contact_start_sec:
		sample_time += interval
	var peak := 0.0
	while sample_time <= finish + 1e-9:
		peak = maxf(peak, _curve_value(curve, sample_time - contact_start_sec))
		sample_time += interval
	return peak


static func _curve_value(curve: Array, local_time_sec: float) -> float:
	if local_time_sec <= 0.0 or local_time_sec >= float(curve[-1]["time_sec"]):
		return 0.0
	var duration := float(curve[-1]["time_sec"])
	var position := local_time_sec / duration * float(curve.size() - 1)
	var lower := clampi(int(floor(position)), 0, curve.size() - 2)
	var weight := position - float(lower)
	return lerpf(
		float(curve[lower]["force_n"]),
		float(curve[lower + 1]["force_n"]),
		weight
	)
