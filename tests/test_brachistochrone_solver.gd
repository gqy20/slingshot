extends RefCounted

const Solver = preload("res://src/simulation/brachistochrone_solver.gd")
const EpisodeLoader = preload("res://src/core/episode_loader.gd")


func _preset(kind: String) -> Dictionary:
	return {
		"physics": {
			"pixels_per_meter": 100.0,
			"gravity_mps2": 9.81,
			"mass_kg": 1.0,
		},
		"scene": {
			"origin_px": Vector2(360, 230),
			"horizontal_span_m": 10.0,
			"vertical_drop_m": 6.0,
			"track_kind": kind,
		},
	}


func run(test) -> void:
	var episode_result := EpisodeLoader.load_path(
		"res://content/episodes/s01e05-shortest-is-not-fastest.json"
	)
	test.check(episode_result["ok"], "S01E05 production storyboard loads")
	if episode_result["ok"]:
		var episode: Dictionary = episode_result["episode"]
		test.check_close(float(episode["duration_sec"]), 219.0, 1.0e-6, "S01E05 content-driven cut is three minutes thirty-nine seconds")
		test.check(episode["beats"].size() == 14, "S01E05 materializes fourteen production beats")
		test.check(String(episode["beats"][9]["id"]) == "finish-slow-motion", "S01E05 reserves a dedicated honest finish replay")
		var formula_steps: Array = episode["story"]["explanation"]["steps"]
		test.check(formula_steps.size() == 4, "S01E05 keeps energy and velocity as separate Typst formula states")
		test.check(String(formula_steps[1]["typst"]).contains("sqrt"), "S01E05 velocity relation uses a real Typst radical")
		test.check(FileAccess.file_exists(String(formula_steps[1]["formula_asset"])), "S01E05 Typst velocity formula asset exists")

	var line := Solver.simulate(_preset("line"), 240, 3.0, 8000)
	var arc := Solver.simulate(_preset("circular_arc"), 240, 3.0, 8000)
	var cycloid := Solver.simulate(_preset("cycloid"), 240, 3.0, 8000)
	var cycloid_time := float(cycloid["metrics"]["arrival_time_sec"])
	var arc_time := float(arc["metrics"]["arrival_time_sec"])
	var exact_line_time := sqrt(2.0 * (10.0 * 10.0 + 6.0 * 6.0) / (9.81 * 6.0))
	test.check(cycloid_time < float(arc["metrics"]["arrival_time_sec"]), "cycloid beats the circular arc")
	test.check(cycloid_time < float(line["metrics"]["arrival_time_sec"]), "cycloid beats the shortest straight path")
	test.check(float(line["metrics"]["path_length_m"]) < float(cycloid["metrics"]["path_length_m"]), "straight path is geometrically shorter than cycloid")
	test.check(float(cycloid["metrics"]["max_energy_error_j"]) < 1.0e-8, "cycloid conserves mechanical energy")
	test.check_close(float(line["metrics"]["arrival_time_sec"]), exact_line_time, 1.0e-6, "segment integration is exact for the straight track")
	test.check_close(arc_time, 1.82057, 0.0005, "monotonic circular arc has the expected arrival time")
	var previous_arc_depth := 0.0
	var arc_is_monotonic := true
	var arc_stays_above_finish := true
	for point_value in arc["path_points_px"]:
		var depth := (Vector2(point_value).y - 230.0) / 100.0
		arc_is_monotonic = arc_is_monotonic and depth + 1.0e-6 >= previous_arc_depth
		arc_stays_above_finish = arc_stays_above_finish and depth <= 6.0 + 1.0e-6
		previous_arc_depth = depth
	test.check(arc_is_monotonic, "circular arc never climbs before the finish")
	test.check(arc_stays_above_finish, "circular arc never dips below the finish")
	test.check_close(previous_arc_depth, 6.0, 1.0e-6, "circular arc reaches its lowest point at the finish")

	var exact := Solver.cycloid_exact_arrival_time(10.0, 6.0, 9.81)
	test.check_close(cycloid_time, exact, 0.0005, "numerical cycloid agrees with exact arrival time")
	var coarse := Solver.simulate(_preset("cycloid"), 240, 3.0, 4000)
	var coarse_time := float(coarse["metrics"]["arrival_time_sec"])
	test.check(absf(coarse_time - cycloid_time) / cycloid_time < 0.0005, "cycloid arrival time converges when integration steps double")

	var final_frame: Dictionary = cycloid["frames"][-1]
	test.check(final_frame["position_m"].distance_to(Vector2(10, 6)) < 1.0e-6, "cycloid ends at the shared finish point")
	test.check_close(float(final_frame["speed_mps"]), 0.0, 1.0e-9, "latched finish state is stationary")
	test.check(float(cycloid["metrics"]["arrival_speed_mps"]) > 0.0, "arrival speed remains available as an explicit metric")
	test.check(float(cycloid["metrics"]["max_speed_mps"]) > float(cycloid["metrics"]["arrival_speed_mps"]), "maximum speed includes the cycloid's slight rise into the finish")
	test.check_close(float(final_frame["distance_traveled_m"]), float(cycloid["metrics"]["path_length_m"]), 1.0e-6, "latched frame retains the complete traveled distance")
	test.check_close(float(final_frame["elapsed_motion_sec"]), cycloid_time, 1.0e-6, "latched frame retains the physical arrival time")
	test.check_close(float(final_frame["height_drop_m"]), 6.0, 1.0e-6, "frame exposes the shared vertical drop")
	var segment_time_sum := 0.0
	var segment_length_sum := 0.0
	for segment_value in cycloid["path_segments"]:
		var segment: Dictionary = segment_value
		segment_time_sum += float(segment["segment_time_sec"])
		segment_length_sum += float(segment["segment_length_m"])
	test.check_close(segment_time_sum, cycloid_time, 1.0e-6, "path segment times sum to the arrival time")
	test.check_close(segment_length_sum, float(cycloid["metrics"]["path_length_m"]), 1.0e-6, "path segment lengths sum to the path length")
