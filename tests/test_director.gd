extends RefCounted

const ShotDirector = preload("res://src/scene/shot_director.gd")
const Telemetry = preload("res://src/core/telemetry.gd")


func run(t) -> void:
	t.check(ShotDirector.phase_for_time(0.5, 12.0, -1.0) == "INTRO", "intro phase")
	t.check(ShotDirector.phase_for_time(2.5, 12.0, -1.0) == "AIM", "aim phase")
	t.check(ShotDirector.phase_for_time(4.0, 12.0, -1.0) == "FLIGHT", "flight phase")
	t.check(ShotDirector.phase_for_time(6.4, 12.0, 6.0) == "IMPACT", "impact phase")
	t.check(ShotDirector.phase_for_time(7.6, 12.0, 6.0) == "AFTERMATH", "aftermath phase")
	t.check(ShotDirector.phase_for_time(11.2, 12.0, 6.0) == "SUMMARY", "summary phase")
	t.check(ShotDirector.phase_for_time(0.2, 1.0, -1.0) == "SUMMARY", "short render summary")

	var telemetry := Telemetry.new()
	telemetry.configure({
		"physics": {
			"pixels_per_meter": 100.0,
			"gravity_mps2": 9.81,
			"bird_mass_kg": 1.0,
			"target_mass_kg": 3.0,
			"spring_k_npm": 160.0,
			"stretch_m": 0.9,
			"efficiency": 0.82,
			"launch_angle_deg": 45.0,
		},
		"scene": {"ground_y_m": 9.2},
	})
	telemetry.update_live(Vector2(240, 760), Vector2(700, -400), Vector2.ZERO, 17, 4.0)
	var live := telemetry.get_snapshot()
	t.check_close(live["speed_mps"], sqrt(65.0), 0.0001, "live speed")
	t.check_close(live["height_m"], 1.6, 0.0001, "live height")
	t.check_close(live["momentum_ns"], sqrt(65.0), 0.0001, "live momentum")

	telemetry.record_collision(
		Vector2(8, 0), Vector2(3, 0), Vector2.ZERO, Vector2(1, 0), 0.01, 6.0
	)
	var collided := telemetry.get_snapshot()
	t.check(collided["collision"]["detected"], "collision detected")
	t.check_close(collided["impulse_ns"], 5.0, 0.0001, "collision impulse")
	t.check_close(collided["average_force_n"], 500.0, 0.0001, "average force estimate")
	telemetry.record_collision(
		Vector2(99, 0), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, 0.01, 7.0
	)
	t.check_close(telemetry.get_snapshot()["collision"]["time_sec"], 6.0, 0.0001, "first collision retained")
	var sidecar_path := "user://slingshot-telemetry-test.json"
	t.check(telemetry.write_sidecar(sidecar_path, "test-shot", 12.0) == OK, "sidecar writes")
	var sidecar_data: Variant = JSON.parse_string(FileAccess.get_file_as_string(sidecar_path))
	t.check(sidecar_data is Dictionary, "sidecar parses as JSON object")
	if sidecar_data is Dictionary:
		var vector_data: Variant = sidecar_data["collision"]["bird_velocity_before_mps"]
		t.check(vector_data is Array and vector_data.size() == 2, "sidecar vectors are numeric arrays")

	var untouched := Telemetry.new()
	untouched.configure({
		"physics": {
			"pixels_per_meter": 100.0,
			"gravity_mps2": 9.81,
			"bird_mass_kg": 1.0,
			"target_mass_kg": 3.0,
			"spring_k_npm": 160.0,
			"stretch_m": 0.9,
			"efficiency": 0.82,
			"launch_angle_deg": 45.0,
		},
		"scene": {"ground_y_m": 9.2},
	})
	t.check(not untouched.get_snapshot()["collision"]["detected"], "no-collision snapshot explicit")
