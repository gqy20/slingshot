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
	canvas.free()
	var errors := EpisodeLayout.validate_static_regions()
	t.check(errors.is_empty(), "episode plot areas avoid every reserved text region")

	var flight_plot := EpisodeLayout.plot_rect_for_phase("FLIGHT")
	var compare_plot := EpisodeLayout.plot_rect_for_phase("COMPARE")
	t.check(
		flight_plot.size.x > compare_plot.size.x,
		"flight prioritizes animation while compare reserves a result column"
	)
	t.check(
		not compare_plot.intersects(EpisodeLayout.RESULT_RECT),
		"compare plot does not sit behind result content"
	)
	for phase in ["QUESTION", "EXPLAIN", "SETUP", "FLIGHT", "COMPARE"]:
		var mapped_ground := EpisodeLayout.map_world(Vector2(0.0, 920.0), phase)
		t.check(
			mapped_ground.y < EpisodeLayout.SUBTITLE_RECT.position.y,
			"%s ground stays above subtitle safe area" % phase
		)
