extends RefCounted

const PresetLoader = preload("res://src/core/preset_loader.gd")
const EpisodeLoader = preload("res://src/core/episode_loader.gd")
const Solver = preload("res://src/simulation/projectile_drag_solver.gd")
const ExperimentRunner = preload("res://src/simulation/experiment_runner.gd")


func run(t) -> void:
	t.check(ExperimentRunner != null, "experiment runner compiles with projectile drag support")
	var loaded := PresetLoader.load_path("res://presets/t001-drag-base.json")
	t.check(loaded["ok"], "T001 drag preset loads")
	if not loaded["ok"]:
		return
	var drag_preset: Dictionary = loaded["preset"]
	var vacuum_preset := drag_preset.duplicate(true)
	vacuum_preset["physics"]["air_density_kg_m3"] = 0.0
	var vacuum := Solver.simulate(vacuum_preset, 240, 6.0)
	var physics: Dictionary = vacuum_preset["physics"]
	var scene: Dictionary = vacuum_preset["scene"]
	var speed := float(physics["launch_speed_mps"])
	var angle := deg_to_rad(float(physics["launch_angle_deg"]))
	var velocity_y := -speed * sin(angle)
	var height_delta := float(scene["landing_y_m"]) - float(scene["launch_position_m"].y)
	var expected_time := (
		-velocity_y + sqrt(velocity_y * velocity_y + 2.0 * float(physics["gravity_mps2"]) * height_delta)
	) / float(physics["gravity_mps2"])
	var expected_range := speed * cos(angle) * expected_time
	t.check_close(
		float(vacuum["metrics"]["flight_range_m"]), expected_range, 0.002,
		"RK4 vacuum range matches analytic projectile"
	)
	var drag := Solver.simulate(drag_preset, 240, 6.0)
	t.check(
		float(drag["metrics"]["flight_range_m"]) < float(vacuum["metrics"]["flight_range_m"]),
		"quadratic drag shortens the representative flight"
	)
	t.check(
		float(drag["metrics"]["dissipated_energy_j"]) > 0.0,
		"quadratic drag dissipates energy"
	)
	var coarse := Solver.simulate(drag_preset, 120, 6.0)
	t.check_close(
		float(coarse["metrics"]["flight_range_m"]),
		float(drag["metrics"]["flight_range_m"]),
		0.01,
		"drag range converges when the time step is halved"
	)
	var scan := Solver.scan_angles(drag_preset, 240, 6.0, 20.0, 70.0, 1.0)
	var best := Solver.best_point(scan)
	t.check(
		float(best["angle_deg"]) < 45.0 and float(best["angle_deg"]) > 30.0,
		"representative drag optimum moves below 45 degrees"
	)
	var vacuum_scan := Solver.scan_angles(vacuum_preset, 240, 6.0, 20.0, 70.0, 1.0)
	var vacuum_best := Solver.best_point(vacuum_scan)
	t.check_close(
		float(vacuum_best["angle_deg"]), 45.0, 0.001,
		"equal-height vacuum scan peaks at 45 degrees"
	)

	var episode_result := EpisodeLoader.load_path(
		"res://content/episodes/s01e03-angle-with-drag.json"
	)
	t.check(episode_result["ok"], "T001 production episode loads")
	if episode_result["ok"]:
		var episode: Dictionary = episode_result["episode"]
		t.check(
			episode["simulation"]["model"] == "projectile_drag",
			"T001 selects the deterministic drag solver"
		)
		t.check_close(episode["duration_sec"], 300.0, 0.001, "T001 targets five minutes")
		t.check(
			episode["story"]["explanation"]["module"] == "drag_effect",
			"T001 uses a data-bound drag explanation"
		)
		var scan_beat: Dictionary = episode["beats"][11]
		var peak_beat: Dictionary = episode["beats"][12]
		t.check(
			scan_beat["visual_sequence"] == peak_beat["visual_sequence"]
			and not String(scan_beat["visual_sequence"]).is_empty(),
			"range curve reveal continues across copy-only beats"
		)
		t.check(
			peak_beat["camera_action"] == "hold",
			"copy-only peak comparison keeps the camera still"
		)
		t.check(
			episode["beats"][13]["overlay"] == "parameter-curve",
			"T001 gives the parameter-dependence paragraph new visual evidence"
		)
		t.check(
			episode["beats"][3]["handoff"] == "trajectory-to-model",
			"T001 preserves the opening trajectory-to-model handoff"
		)
		t.check(
			episode["beats"][11]["handoff"] == "landings-to-chart",
			"T001 preserves the data-bound landing-to-chart handoff"
		)
		t.check(
			episode["beats"][14]["handoff"] == "chart-to-trajectories",
			"T001 preserves the chart-to-trajectory conclusion handoff"
		)
		t.check_close(
			float(episode["beats"][15]["result_reveal"]), 0.16, 0.0001,
			"T001 stages the final result instead of revealing it at the cut"
		)
