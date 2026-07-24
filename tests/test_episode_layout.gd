extends RefCounted

const EpisodeLayout = preload("res://src/video/episode_layout.gd")
const EpisodeCanvas = preload("res://src/video/episode_canvas.gd")
const EpisodeHud = preload("res://src/video/episode_hud.gd")


func run(t) -> void:
	t.check(
		EpisodeLayout.world_scale("FLIGHT", "immersive") > EpisodeLayout.world_scale("FLIGHT"),
		"immersive mode gives the physical world more screen area"
	)
	t.check(EpisodeCanvas != null and EpisodeHud != null, "episode render components compile")
	var canvas := EpisodeCanvas.new()
	canvas.phase = "COMPARE"
	canvas.current_beat = {"layers": ["world", "subjects", "trajectories"]}
	t.check(not canvas._winner_emphasis_enabled(), "immersive counterexample removes winner celebration")
	canvas.current_beat = {"layers": ["world", "results"]}
	t.check(canvas._winner_emphasis_enabled(), "measurement result enables winner emphasis")
	canvas.current_beat = {
		"phase": "EXPLAIN",
		"layers": ["world", "annotations"],
		"overlay": "spring-energy",
		"at": 25.0,
		"duration": 10.0,
		"formula_step": 1,
	}
	canvas.phase = "EXPLAIN"
	canvas.video_time_sec = 25.0
	t.check(not canvas._show_physical_stage(), "energy diagram removes the unrelated sling and ground")
	t.check_close(canvas._spring_extension_factor(), 1.0, 0.0001, "spring starts its purposeful x-to-2x transition without jumping")
	canvas.video_time_sec = 25.8
	t.check_close(canvas._spring_extension_factor(), 2.0, 0.0001, "spring reaches the doubled extension after the transition")
	t.check(canvas._spring_dimension_label(1.0) == "x", "base extension uses the x dimension label")
	t.check(canvas._spring_dimension_label(1.5) == "x → 2x", "dimension label explains the transition while the spring moves")
	t.check(canvas._spring_dimension_label(2.0) == "2x", "doubled extension uses the 2x dimension label")
	canvas.episode = {"story": {"question_sec": 15.0}}
	canvas.video_time_sec = 24.9
	var reveal_before_copy_boundary := canvas._energy_bar_reveal(3, 4)
	canvas.video_time_sec = 25.1
	var reveal_after_copy_boundary := canvas._energy_bar_reveal(3, 4)
	t.check_close(reveal_before_copy_boundary, 1.0, 0.0001, "energy bars finish their first reveal")
	t.check_close(reveal_after_copy_boundary, 1.0, 0.0001, "energy bars do not reset at the next explanation beat")
	var errors := EpisodeLayout.validate_static_regions()
	t.check(errors.is_empty(), "episode plot areas avoid every reserved text region")

	var flight_plot := EpisodeLayout.plot_rect_for_phase("FLIGHT")
	var compare_plot := EpisodeLayout.plot_rect_for_phase("COMPARE")
	t.check(
		compare_plot.size.x >= flight_plot.size.x,
		"comparison uses the world instead of reserving a dashboard column"
	)
	t.check(
		compare_plot.intersects(EpisodeLayout.RESULT_RECT),
		"transparent result typography can share the physical stage"
	)
	var previous_result_cell := Rect2()
	for index in range(5):
		var result_cell := EpisodeLayout.result_rail_cell(index, 5)
		t.check(
			EpisodeLayout.RESULT_RAIL_RECT.encloses(result_cell),
			"result rail cell %d stays inside the dedicated comparison band" % index
		)
		if index > 0:
			t.check(
				not previous_result_cell.intersects(result_cell),
				"result rail cells do not overlap"
			)
		previous_result_cell = result_cell
	var trajectory := PackedVector2Array([
		Vector2(240, 760),
		Vector2(360, 540),
		Vector2(480, 620),
		Vector2(620, 920),
	])
	t.check(
		canvas._trajectory_apex(trajectory) == Vector2(360, 540),
		"height annotation follows the actual trajectory apex"
	)
	canvas.free()
	for phase in ["QUESTION", "EXPLAIN", "SETUP", "FLIGHT", "COMPARE"]:
		var mapped_ground := EpisodeLayout.map_world(Vector2(0.0, 920.0), phase)
		t.check(
			mapped_ground.y < EpisodeLayout.SUBTITLE_RECT.position.y,
			"%s ground stays above subtitle safe area" % phase
		)
